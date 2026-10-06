-- S3: Least-privilege protection for login lockout state and auth helper RPCs.
-- Forward-only; no application rows are read or changed by this migration.
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.login_attempts') IS NULL THEN
        RAISE EXCEPTION 'S3 requires public.login_attempts';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.login_attempts'::regclass
          AND attname = 'email' AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.login_attempts'::regclass
          AND attname = 'attempts' AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.login_attempts'::regclass
          AND attname = 'locked_until' AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'S3 login_attempts schema did not match reviewed prerequisites';
    END IF;
    IF to_regprocedure('public.record_failed_login(text)') IS NULL
       OR to_regprocedure('public.reset_login_lockout(text)') IS NULL
       OR to_regprocedure('public.delete_user(uuid)') IS NULL THEN
        RAISE EXCEPTION 'S3 expected auth security function signature is missing';
    END IF;
END;
$$;

ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read login attempts" ON public.login_attempts;

-- Fail closed if an unreviewed SELECT/ALL policy would preserve row visibility.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'login_attempts'
          AND cmd IN ('SELECT', 'ALL')
    ) THEN
        RAISE EXCEPTION 'S3 found an unreviewed login_attempts read policy';
    END IF;
END;
$$;

REVOKE ALL PRIVILEGES ON TABLE public.login_attempts FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES (email, attempts, locked_until)
    ON TABLE public.login_attempts FROM PUBLIC, anon, authenticated;

-- Failed login happens before authentication. The browser supplies an arbitrary
-- email and therefore is not a safe principal for changing shared lockout state.
-- Keep the function for trusted backend use only; pin its resolution context.
ALTER FUNCTION public.record_failed_login(text)
    SET search_path = pg_catalog, public, pg_temp;
REVOKE ALL ON FUNCTION public.record_failed_login(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_failed_login(text) TO service_role;

-- Preserve successful-login self-reset and active-admin support, but reject
-- inactive profiles and prevent ordinary users from resetting another account.
CREATE OR REPLACE FUNCTION public.reset_login_lockout(user_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
    actor_id uuid := auth.uid();
    actor_email text;
    actor_role text;
    actor_active boolean;
    requested_email text := lower(btrim(user_email));
BEGIN
    IF actor_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    SELECT lower(btrim(u.email))
      INTO actor_email
      FROM auth.users AS u
     WHERE u.id = actor_id;

    SELECT upper(coalesce(p.role, '')), p.is_active
      INTO actor_role, actor_active
      FROM public.profiles AS p
     WHERE p.id = actor_id;

    IF actor_email IS NULL OR actor_active IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'An active account is required' USING ERRCODE = '42501';
    END IF;

    IF actor_role = 'ADMIN' THEN
        NULL;
    ELSIF actor_email = requested_email THEN
        NULL;
    ELSE
        RAISE EXCEPTION 'Not authorized to reset this login lockout' USING ERRCODE = '42501';
    END IF;

    UPDATE public.login_attempts
       SET attempts = 0, locked_until = NULL
     WHERE lower(email) = requested_email;
END;
$$;
REVOKE ALL ON FUNCTION public.reset_login_lockout(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_login_lockout(text) TO authenticated;

-- Preserve the reviewed active-admin/role/body authorization exactly; change
-- only the execution path and execution audience.
ALTER FUNCTION public.delete_user(uuid)
    SET search_path = pg_catalog, public, auth, pg_temp;
REVOKE ALL ON FUNCTION public.delete_user(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user(uuid) TO authenticated;

COMMIT;
