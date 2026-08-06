-- Supabase Schema for Aegis HR

-- 1. Time Punches Table
CREATE TABLE time_punches (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    employee_id UUID NOT NULL, -- References auth.users(id) in a real setup
    punch_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    punch_type VARCHAR(10) CHECK (punch_type IN ('IN', 'OUT')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS (Row Level Security)
ALTER TABLE time_punches ENABLE ROW LEVEL SECURITY;

-- Allow anonymous inserts for the prototype
CREATE POLICY "Allow anonymous inserts" ON time_punches
    FOR INSERT WITH CHECK (true);

-- Allow anonymous selects for the prototype
CREATE POLICY "Allow anonymous selects" ON time_punches
    FOR SELECT USING (true);


-- 2. Leave Requests Table
CREATE TABLE leave_requests (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    employee_id UUID NOT NULL,
    leave_type VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow anonymous inserts" ON leave_requests FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow anonymous selects" ON leave_requests FOR SELECT USING (true);


-- 3. Announcements Table
CREATE TABLE announcements (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    icon VARCHAR(50) DEFAULT 'megaphone',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow anonymous selects" ON announcements FOR SELECT USING (true);

-- Insert dummy announcements
INSERT INTO announcements (title, content, icon) VALUES 
('Q3 Townhall Meeting', 'Join us this Friday for the quarterly company update. Location: Main Auditorium & Zoom.', 'megaphone'),
('New Wellness Benefits Added', 'We have added gym memberships to our health coverage. Check your benefits portal.', 'heart-pulse');

-- 4. Profiles Table (For Role Management)
CREATE TABLE profiles (
    id UUID REFERENCES auth.users(id) PRIMARY KEY,
    role VARCHAR(20) DEFAULT 'EMPLOYEE' CHECK (role IN ('ADMIN', 'EMPLOYEE')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read their own profile" ON profiles FOR SELECT USING (auth.uid() = id);

-- ==========================================
-- ADMIN SEED SCRIPT
-- ==========================================
-- Run this block in the Supabase SQL Editor to securely inject the admin account.
-- Email: privatepple@gmail.com
-- Password: 0912577754

DO $$
DECLARE
  new_user_id UUID := gen_random_uuid();
BEGIN
  -- 1. Insert into auth.users using pgcrypto for the bcrypt password hash
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password, 
    email_confirmed_at, recovery_sent_at, last_sign_in_at, 
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
    confirmation_token, email_change, email_change_token_new, recovery_token
  )
  VALUES (
    '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated', 'privatepple@gmail.com', 
    crypt('0912577754', gen_salt('bf')), 
    now(), now(), now(), 
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), 
    '', '', '', ''
  );

  -- 2. Insert into the identities table
  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
  )
  VALUES (
    new_user_id::text, new_user_id, format('{"sub":"%s","email":"%s"}', new_user_id::text, 'privatepple@gmail.com')::jsonb, 'email', now(), now(), now(), gen_random_uuid()
  );

  -- 3. Assign the ADMIN role in our profiles table
  INSERT INTO public.profiles (id, role)
  VALUES (new_user_id, 'ADMIN');

END $$;

