-- FIX FOR COMMUNITY CHAT FOREIGN KEY
ALTER TABLE public.community_chat DROP CONSTRAINT IF EXISTS community_chat_user_id_fkey;
ALTER TABLE public.community_chat ADD CONSTRAINT community_chat_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- FIX PROFILES ROLE CHECK CONSTRAINT
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('ADMIN', 'MANAGER', 'SUPERVISOR', 'EMPLOYEE'));

-- DROP ALL EXISTING VERSIONS OF THE FUNCTION (Postgres allows overloading, so we must be specific)
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.create_user_by_admin();

-- RECREATE WITH CORRECT RETURN TYPE (UUID) AND ARGUMENTS
CREATE OR REPLACE FUNCTION public.create_user_by_admin(
    new_email TEXT,
    new_password TEXT,
    new_role VARCHAR(20) DEFAULT 'EMPLOYEE',
    new_job_title VARCHAR(100) DEFAULT NULL,
    new_full_name VARCHAR(255) DEFAULT NULL,
    new_iqama VARCHAR(50) DEFAULT NULL,
    new_phone VARCHAR(50) DEFAULT NULL
) RETURNS UUID AS $$
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

    -- Insert into auth.users (Supabase uses this for actual login)
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password, 
        email_confirmed_at, recovery_sent_at, last_sign_in_at, 
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
        confirmation_token, email_change, email_change_token_new, recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated', new_email,
        extensions.crypt(new_password, extensions.gen_salt('bf')),
        now(), now(), now(), 
        '{"provider":"email","providers":["email"]}', '{}', now(), now(), 
        '', '', '', ''
    );

    -- Insert into the identities table
    INSERT INTO auth.identities (
        provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
    )
    VALUES (
        new_user_id::text, new_user_id, format('{"sub":"%s","email":"%s"}', new_user_id::text, new_email)::jsonb, 'email', now(), now(), now(), gen_random_uuid()
    );

    -- Insert into public.profiles
    INSERT INTO public.profiles (id, role, job_title, full_name, iqama_number, phone_number)
    VALUES (new_user_id, TRIM(UPPER(new_role)), new_job_title, new_full_name, new_iqama, new_phone);

    RETURN new_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, extensions;

-- RELOAD SCHEMA CACHE
NOTIFY pgrst, 'reload schema';
