-- One-time employee login synchronization.
--
-- Install this function in the Supabase SQL editor, then call it while signed
-- in as a system administrator through the application RPC client. The
-- password is accepted as an argument so it is not stored in source control.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.sync_employee_login_accounts(
    temporary_password TEXT,
    apply_changes BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions, pg_temp
AS $$
DECLARE
    caller_is_admin BOOLEAN;
    admin_user_id UUID;
    employee_record RECORD;
    account_count INTEGER := 0;
    deleted_count INTEGER := 0;
    email_accounts JSONB := '[]'::JSONB;
    missing_email_employees JSONB := '[]'::JSONB;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = auth.uid()
          AND UPPER(COALESCE(role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
    ) INTO caller_is_admin;

    IF NOT caller_is_admin THEN
        RAISE EXCEPTION 'Only a system administrator can synchronize employee accounts';
    END IF;

    IF apply_changes AND (
        temporary_password IS NULL
        OR LENGTH(temporary_password) < 8
        OR temporary_password !~ '[A-Z]'
        OR temporary_password !~ '[a-z]'
        OR temporary_password !~ '[0-9]'
    ) THEN
        RAISE EXCEPTION 'The temporary password does not meet the minimum security requirements';
    END IF;

    admin_user_id := auth.uid();

    FOR employee_record IN
        SELECT
            profile.id,
            profile.full_name,
            profile.emp_index,
            profile.role,
            NULLIF(BTRIM(auth_user.email), '') AS email
        FROM public.profiles profile
        LEFT JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE UPPER(COALESCE(profile.role, 'EMPLOYEE')) NOT IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
        ORDER BY profile.emp_index NULLS LAST, profile.full_name
    LOOP
        IF employee_record.email IS NULL THEN
            missing_email_employees := missing_email_employees || jsonb_build_array(jsonb_build_object(
                'id', employee_record.id,
                'employee_number', employee_record.emp_index,
                'name', employee_record.full_name,
                'role', employee_record.role
            ));

            IF apply_changes THEN
                -- The user requested complete removal. Delete contracts first
                -- so the normal employee deletion routine cannot archive and
                -- retain personal details for an employee without an email.
                DELETE FROM public.contracts WHERE employee_id = employee_record.id;

                -- Reuse the established dependency-aware deletion routine.
                -- auth.uid() remains the signed-in administrator.
                PERFORM public.archive_and_delete_employee(employee_record.id);
                deleted_count := deleted_count + 1;
            END IF;
        ELSE
            email_accounts := email_accounts || jsonb_build_array(jsonb_build_object(
                'id', employee_record.id,
                'employee_number', employee_record.emp_index,
                'name', employee_record.full_name,
                'email', LOWER(employee_record.email),
                'role', employee_record.role
            ));

            IF apply_changes THEN
                UPDATE auth.users
                SET
                    email = LOWER(employee_record.email),
                    encrypted_password = extensions.crypt(temporary_password, extensions.gen_salt('bf')),
                    email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
                    confirmation_token = '',
                    recovery_token = '',
                    email_change = '',
                    email_change_token_new = '',
                    raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::JSONB)
                        || '{"provider":"email","providers":["email"]}'::JSONB,
                    raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::JSONB)
                        || jsonb_build_object('temporary_password', TRUE),
                    updated_at = NOW()
                WHERE id = employee_record.id;

                UPDATE auth.identities
                SET
                    provider_id = LOWER(employee_record.email),
                    identity_data = COALESCE(identity_data, '{}'::JSONB)
                        || jsonb_build_object('sub', employee_record.id::TEXT, 'email', LOWER(employee_record.email)),
                    updated_at = NOW()
                WHERE user_id = employee_record.id AND provider = 'email';

                IF NOT FOUND THEN
                    INSERT INTO auth.identities (
                        id, provider_id, user_id, identity_data, provider,
                        last_sign_in_at, created_at, updated_at
                    ) VALUES (
                        gen_random_uuid(), LOWER(employee_record.email), employee_record.id,
                        jsonb_build_object('sub', employee_record.id::TEXT, 'email', LOWER(employee_record.email)),
                        'email', NOW(), NOW(), NOW()
                    );
                END IF;

                account_count := account_count + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'applied', apply_changes,
        'accounts_to_create_or_reset', jsonb_array_length(email_accounts),
        'employees_to_delete', jsonb_array_length(missing_email_employees),
        'accounts_updated', account_count,
        'employees_deleted', deleted_count,
        'accounts', email_accounts,
        'missing_email_employees', missing_email_employees,
        'executed_by', admin_user_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.sync_employee_login_accounts(TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_employee_login_accounts(TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.sync_employee_login_accounts(TEXT, BOOLEAN) IS
'Previews or applies employee login synchronization. Non-admin employees with email receive the supplied temporary password; non-admin employees without email are fully removed.';

NOTIFY pgrst, 'reload schema';
