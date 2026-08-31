-- Admin-only login email and credential management.
-- Passwords are accepted as RPC parameters and are never stored as plain text.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_get_user_email(target_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    result_email TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'ADMIN'
    ) THEN
        RAISE EXCEPTION 'Only an administrator can view login emails' USING ERRCODE = '42501';
    END IF;

    SELECT LOWER(BTRIM(email)) INTO result_email
    FROM auth.users
    WHERE id = target_user_id;

    IF result_email IS NULL THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;
    RETURN result_email;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_user_credentials(
    target_user_id UUID,
    new_email TEXT,
    new_password TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    normalized_email TEXT := LOWER(BTRIM(new_email));
    previous_email TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'ADMIN'
    ) THEN
        RAISE EXCEPTION 'Only an administrator can update login credentials' USING ERRCODE = '42501';
    END IF;
    IF normalized_email IS NULL OR normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'Enter a valid email address' USING ERRCODE = '22023';
    END IF;
    IF new_password IS NOT NULL AND LENGTH(new_password) < 8 THEN
        RAISE EXCEPTION 'Password must contain at least 8 characters' USING ERRCODE = '22023';
    END IF;

    SELECT LOWER(BTRIM(email)) INTO previous_email FROM auth.users WHERE id = target_user_id FOR UPDATE;
    IF previous_email IS NULL THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;
    IF EXISTS (SELECT 1 FROM auth.users WHERE LOWER(email) = normalized_email AND id <> target_user_id) THEN
        RAISE EXCEPTION 'Another user already uses this email address' USING ERRCODE = '23505';
    END IF;

    UPDATE auth.users
    SET email = normalized_email,
        email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
        encrypted_password = CASE
            WHEN new_password IS NULL THEN encrypted_password
            ELSE crypt(new_password, gen_salt('bf'))
        END,
        updated_at = NOW()
    WHERE id = target_user_id;

    UPDATE auth.identities
    SET identity_data = COALESCE(identity_data, '{}'::JSONB)
        || JSONB_BUILD_OBJECT('email', normalized_email),
        updated_at = NOW()
    WHERE user_id = target_user_id AND provider = 'email';

    IF previous_email <> normalized_email THEN
        UPDATE public.login_attempts SET email = normalized_email WHERE LOWER(email) = previous_email;
    END IF;
    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_user_email(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_update_user_credentials(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_email(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user_credentials(UUID, TEXT, TEXT) TO authenticated;

COMMIT;
