-- Fixes "Permission Denied" when an Admin, System Admin, or HR Manager
-- creates an employee from User Management.

DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT);

CREATE OR REPLACE FUNCTION public.create_user_by_admin(
    new_email TEXT,
    new_password TEXT,
    new_role VARCHAR(20) DEFAULT 'EMPLOYEE',
    new_job_title VARCHAR(100) DEFAULT NULL,
    new_full_name VARCHAR(255) DEFAULT NULL,
    new_iqama VARCHAR(50) DEFAULT NULL,
    new_phone VARCHAR(50) DEFAULT NULL,
    new_employee_id TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    new_user_id UUID := gen_random_uuid();
    authorized BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(COALESCE(p.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
              OR UPPER(COALESCE(p.job_title, '')) = 'HR MANAGER'
          )
    ) INTO authorized;

    IF NOT authorized THEN
        RAISE EXCEPTION 'Unauthorized: only Admin or HR Manager accounts can create users'
            USING ERRCODE = '42501';
    END IF;

    IF NULLIF(BTRIM(new_email), '') IS NULL OR NULLIF(new_password, '') IS NULL THEN
        RAISE EXCEPTION 'Email and password are required' USING ERRCODE = '22023';
    END IF;

    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at, confirmation_token, email_change,
        email_change_token_new, recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated',
        LOWER(BTRIM(new_email)), extensions.crypt(new_password, extensions.gen_salt('bf')),
        now(), '{"provider":"email","providers":["email"]}', '{}',
        now(), now(), '', '', '', ''
    );

    INSERT INTO auth.identities (
        provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
    ) VALUES (
        new_user_id::text, new_user_id,
        jsonb_build_object('sub', new_user_id::text, 'email', LOWER(BTRIM(new_email))),
        'email', now(), now(), now(), gen_random_uuid()
    );

    INSERT INTO public.profiles (id, role, job_title, full_name, iqama_number, phone_number, emp_index)
    VALUES (
        new_user_id, UPPER(COALESCE(NULLIF(BTRIM(new_role), ''), 'EMPLOYEE')),
        NULLIF(BTRIM(new_job_title), ''), NULLIF(BTRIM(new_full_name), ''),
        NULLIF(BTRIM(new_iqama), ''), NULLIF(BTRIM(new_phone), ''),
        NULLIF(BTRIM(new_employee_id), '')::integer
    );

    RETURN new_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';
