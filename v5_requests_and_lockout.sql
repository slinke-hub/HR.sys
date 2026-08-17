-- 1. Create requests table
CREATE TABLE IF NOT EXISTS public.requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    request_type TEXT NOT NULL,
    leave_type TEXT,
    status TEXT DEFAULT 'Pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own requests or admins view all"
    ON public.requests FOR SELECT
    USING (
        employee_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')
        )
    );

CREATE POLICY "Users can insert their own requests"
    ON public.requests FOR INSERT
    WITH CHECK ( 
        employee_id = auth.uid() OR 
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')
        ) 
    );

CREATE POLICY "Admins can update requests"
    ON public.requests FOR UPDATE
    USING ( EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')
        ) );

CREATE POLICY "Admins can delete requests"
    ON public.requests FOR DELETE
    USING ( EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')
        ) );

-- 2. Create login_attempts table
CREATE TABLE IF NOT EXISTS public.login_attempts (
    email TEXT PRIMARY KEY,
    attempts INT DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE
);

ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;
-- Allow anonymous read so client can check if locked BEFORE trying to login
CREATE POLICY "Anyone can read login attempts"
    ON public.login_attempts FOR SELECT
    USING (true);

-- 3. Create record_failed_login RPC
CREATE OR REPLACE FUNCTION public.record_failed_login(user_email TEXT)
RETURNS void AS $$
BEGIN
    INSERT INTO public.login_attempts (email, attempts, locked_until)
    VALUES (user_email, 1, NULL)
    ON CONFLICT (email) DO UPDATE 
    SET attempts = login_attempts.attempts + 1,
        locked_until = CASE 
            WHEN login_attempts.attempts + 1 >= 3 THEN NOW() + INTERVAL '24 hours'
            ELSE NULL
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Create reset_login_lockout RPC
CREATE OR REPLACE FUNCTION public.reset_login_lockout(user_email TEXT)
RETURNS void AS $$
DECLARE
    caller_role TEXT;
    caller_email TEXT;
BEGIN
    -- Get caller role
    SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
    
    -- Get caller email
    SELECT email INTO caller_email FROM auth.users WHERE id = auth.uid();

    -- Allow if Admin OR if the caller is the owner of the email
    IF caller_role = 'ADMIN' OR caller_email = user_email THEN
        UPDATE public.login_attempts
        SET attempts = 0, locked_until = NULL
        WHERE email = user_email;
    ELSE
        RAISE EXCEPTION 'Unauthorized';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Create reset_user_password RPC
-- Note: uses pgcrypto's crypt() function
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public.reset_user_password(target_user_id UUID, new_password TEXT)
RETURNS void AS $$
BEGIN
    -- Only allow admins to execute
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    UPDATE auth.users
    SET encrypted_password = crypt(new_password, gen_salt('bf'))
    WHERE id = target_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Create delete_user RPC
CREATE OR REPLACE FUNCTION public.delete_user(target_user_id UUID)
RETURNS void AS $$
BEGIN
    -- Only allow admins to execute
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Perform a soft delete by marking the user as inactive
    -- This prevents 409 Conflict errors from other tables that reference this user
    UPDATE public.profiles SET is_active = false WHERE id = target_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Add active column to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
