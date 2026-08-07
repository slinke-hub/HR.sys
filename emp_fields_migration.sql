-- 1. Add new columns to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS full_name VARCHAR(255);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS iqama_number VARCHAR(50);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_number VARCHAR(50);
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS emp_index SERIAL;

-- 2. Update the RPC function to accept these new fields
CREATE OR REPLACE FUNCTION create_user_by_admin(
    new_email TEXT,
    new_password TEXT,
    new_role VARCHAR(20) DEFAULT 'EMPLOYEE',
    new_job_title VARCHAR(100) DEFAULT NULL,
    new_full_name VARCHAR(255) DEFAULT NULL,
    new_iqama VARCHAR(50) DEFAULT NULL,
    new_phone VARCHAR(50) DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    new_user_id UUID;
    is_admin BOOLEAN;
BEGIN
    -- Check if the caller is an Admin
    SELECT EXISTS (
        SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'
    ) INTO is_admin;

    IF NOT is_admin THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can create users';
    END IF;

    -- Generate a new UUID for the user
    new_user_id := gen_random_uuid();

    -- Insert into auth.users
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password, 
        email_confirmed_at, recovery_sent_at, last_sign_in_at, 
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
        confirmation_token, email_change, email_change_token_new, recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated', new_email,
        crypt(new_password, gen_salt('bf')),
        NOW(), NOW(), NOW(), 
        '{"provider":"email","providers":["email"]}', '{}', NOW(), NOW(),
        '', '', '', ''
    );

    -- Insert into auth.identities
    INSERT INTO auth.identities (
        provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
    ) VALUES (
        new_user_id::TEXT, new_user_id, format('{"sub":"%s","email":"%s"}', new_user_id::TEXT, new_email)::jsonb, 
        'email', NOW(), NOW(), NOW(), gen_random_uuid()
    );

    -- Assign the role, job title, and new fields in profiles table
    INSERT INTO public.profiles (id, role, job_title, full_name, iqama_number, phone_number)
    VALUES (new_user_id, new_role, new_job_title, new_full_name, new_iqama, new_phone);

    RETURN jsonb_build_object('id', new_user_id, 'email', new_email);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
