-- Reviewed production migration generated from the verified service artifact.
-- Source artifact: auth_backend_services.sql
-- No environment reference, test identity, synthetic fixture, or cleanup harness is included.
-- Auth/session security reconciliation for the HR.sys project.
-- This file is intentionally reviewed production and contains no user data or secrets.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_get_user_email(target_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE result_email text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND role = 'ADMIN'
          AND is_active IS DISTINCT FROM FALSE
    ) THEN
        RAISE EXCEPTION 'Only an active administrator can view login emails' USING ERRCODE = '42501';
    END IF;
    SELECT lower(btrim(email)) INTO result_email FROM auth.users WHERE id = target_user_id;
    IF result_email IS NULL THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;
    RETURN result_email;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_user_credentials(
    target_user_id uuid,
    new_email text,
    new_password text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    normalized_email text := lower(btrim(new_email));
    previous_email text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND role = 'ADMIN'
          AND is_active IS DISTINCT FROM FALSE
    ) THEN
        RAISE EXCEPTION 'Only an active administrator can update login credentials' USING ERRCODE = '42501';
    END IF;
    IF normalized_email IS NULL OR normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'Enter a valid email address' USING ERRCODE = '22023';
    END IF;
    IF new_password IS NOT NULL AND length(new_password) < 12 THEN
        RAISE EXCEPTION 'Password must contain at least 12 characters' USING ERRCODE = '22023';
    END IF;
    SELECT lower(btrim(email)) INTO previous_email FROM auth.users WHERE id = target_user_id FOR UPDATE;
    IF previous_email IS NULL THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;
    IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = normalized_email AND id <> target_user_id) THEN
        RAISE EXCEPTION 'Another user already uses this email address' USING ERRCODE = '23505';
    END IF;
    UPDATE auth.users
       SET email = normalized_email,
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           encrypted_password = CASE WHEN new_password IS NULL THEN encrypted_password ELSE extensions.crypt(new_password, extensions.gen_salt('bf')) END,
           updated_at = now()
     WHERE id = target_user_id;
    UPDATE auth.identities
       SET identity_data = coalesce(identity_data, '{}'::jsonb) || jsonb_build_object('email', normalized_email),
           updated_at = now()
     WHERE user_id = target_user_id AND provider = 'email';
    IF previous_email <> normalized_email THEN
        UPDATE public.login_attempts SET email = normalized_email WHERE lower(email) = previous_email;
    END IF;
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reset_user_password(target_user_id uuid, new_password text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND role = 'ADMIN'
          AND is_active IS DISTINCT FROM FALSE
    ) THEN
        RAISE EXCEPTION 'Only an active administrator can reset passwords' USING ERRCODE = '42501';
    END IF;
    IF new_password IS NULL OR length(new_password) < 12 THEN
        RAISE EXCEPTION 'Password must contain at least 12 characters' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = target_user_id) THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;
    UPDATE auth.users
       SET encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     WHERE id = target_user_id;
    INSERT INTO public.admin_password_reset_audit(actor_user_id, target_user_id)
    VALUES (auth.uid(), target_user_id);
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_user_lock(target_user_id uuid, should_lock boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE target_email text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'ADMIN' AND is_active IS DISTINCT FROM FALSE
    ) THEN
        RAISE EXCEPTION 'Only an active administrator can lock or unlock users' USING ERRCODE = '42501';
    END IF;
    IF target_user_id = auth.uid() AND should_lock THEN
        RAISE EXCEPTION 'Administrators cannot lock their own account' USING ERRCODE = '22023';
    END IF;
    SELECT lower(email) INTO target_email FROM auth.users WHERE id = target_user_id;
    IF target_email IS NULL THEN RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002'; END IF;
    INSERT INTO public.login_attempts(email, attempts, locked_until)
    VALUES (target_email, CASE WHEN should_lock THEN 3 ELSE 0 END, CASE WHEN should_lock THEN now() + interval '100 years' ELSE NULL END)
    ON CONFLICT (email) DO UPDATE SET attempts = excluded.attempts, locked_until = excluded.locked_until;
END;
$$;

REVOKE ALL ON FUNCTION public.reset_user_password(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_get_user_email(uuid), public.admin_update_user_credentials(uuid, text, text), public.admin_reset_user_password(uuid, text), public.admin_set_user_lock(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_email(uuid), public.admin_update_user_credentials(uuid, text, text), public.admin_reset_user_password(uuid, text), public.admin_set_user_lock(uuid, boolean) TO authenticated;

COMMIT;
