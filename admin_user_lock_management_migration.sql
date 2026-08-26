-- Admin-managed account locks and normalized login-attempt email matching.
BEGIN;

UPDATE public.login_attempts
SET email = LOWER(BTRIM(email));

CREATE OR REPLACE FUNCTION public.admin_list_user_lock_status()
RETURNS TABLE (
    user_id UUID,
    email TEXT,
    attempts INTEGER,
    locked_until TIMESTAMPTZ,
    is_locked BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Only an administrator can view account lock status' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT users.id,
           LOWER(users.email),
           COALESCE(attempts.attempts, 0),
           attempts.locked_until,
           COALESCE(attempts.locked_until > NOW(), FALSE)
    FROM auth.users AS users
    LEFT JOIN public.login_attempts AS attempts ON attempts.email = LOWER(users.email)
    ORDER BY users.email;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_user_lock(target_user_id UUID, should_lock BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    target_email TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Only an administrator can lock or unlock users' USING ERRCODE = '42501';
    END IF;
    IF target_user_id = auth.uid() AND should_lock THEN
        RAISE EXCEPTION 'Administrators cannot lock their own account' USING ERRCODE = '22023';
    END IF;

    SELECT LOWER(email) INTO target_email FROM auth.users WHERE id = target_user_id;
    IF target_email IS NULL THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO public.login_attempts (email, attempts, locked_until)
    VALUES (target_email, CASE WHEN should_lock THEN 3 ELSE 0 END,
            CASE WHEN should_lock THEN NOW() + INTERVAL '100 years' ELSE NULL END)
    ON CONFLICT (email) DO UPDATE
    SET attempts = EXCLUDED.attempts,
        locked_until = EXCLUDED.locked_until;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_user_lock_status() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_user_lock(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_user_lock_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_user_lock(UUID, BOOLEAN) TO authenticated;

-- Requested immediate unlock. This is idempotent and is safe to rerun.
INSERT INTO public.login_attempts (email, attempts, locked_until)
VALUES ('hussain.bhhari@muqam.net', 0, NULL)
ON CONFLICT (email) DO UPDATE SET attempts = 0, locked_until = NULL;

COMMIT;
