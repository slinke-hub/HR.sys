-- Supabase Schema for MUQAM HR

-- 1. Time Punches Table
CREATE TABLE time_punches (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    punch_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    punch_type VARCHAR(10) CHECK (punch_type IN ('IN', 'OUT')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE time_punches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Employees can insert their own punches" ON time_punches
    FOR INSERT WITH CHECK (auth.uid() = employee_id);

CREATE POLICY "Employees can view their own punches" ON time_punches
    FOR SELECT USING (auth.uid() = employee_id OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

CREATE POLICY "Admins can view all punches" ON time_punches
    FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));


-- 2. Leave Requests Table
CREATE TABLE leave_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    leave_type VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Employees can insert their own leave requests" ON leave_requests 
    FOR INSERT WITH CHECK (auth.uid() = employee_id);

CREATE POLICY "Employees can view their own leave requests" ON leave_requests 
    FOR SELECT USING (auth.uid() = employee_id OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

CREATE POLICY "Admins can update leave requests" ON leave_requests 
    FOR UPDATE USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));


-- 3. Announcements Table
CREATE TABLE announcements (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
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
CREATE TABLE IF NOT EXISTS profiles (
    id UUID REFERENCES auth.users(id) PRIMARY KEY,
    role VARCHAR(20) DEFAULT 'EMPLOYEE' CHECK (role IN ('ADMIN', 'MANAGER', 'EMPLOYEE')),
    job_title VARCHAR(100),
    emp_index BIGSERIAL UNIQUE,
    avatar_url TEXT,
    display_name VARCHAR(100) CHECK (display_name IS NULL OR BTRIM(display_name) <> ''),
    manager_id UUID REFERENCES auth.users(id),
    base_salary DECIMAL(10, 2) DEFAULT 3000.00,
    annual_leave_allowance INTEGER DEFAULT 30,
    sick_leave_allowance INTEGER DEFAULT 10,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Note: For existing databases, you may need to run these ALTER statements manually:
-- ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS manager_id UUID REFERENCES auth.users(id);
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS base_salary DECIMAL(10, 2) DEFAULT 3000.00;
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS annual_leave_allowance INTEGER DEFAULT 30;
-- ALTER TABLE profiles ADD COLUMN IF NOT EXISTS sick_leave_allowance INTEGER DEFAULT 10;
-- ALTER TABLE profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('ADMIN', 'MANAGER', 'EMPLOYEE'));

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read their own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Admins can read all profiles" ON profiles FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

CREATE OR REPLACE FUNCTION public.protect_profile_privileged_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE caller_role TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
    IF caller_role = 'ADMIN' THEN RETURN NEW; END IF;
    IF (to_jsonb(NEW) - ARRAY['full_name', 'display_name', 'iqama_number', 'phone_number', 'avatar_url', 'last_login', 'birth_date']::TEXT[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['full_name', 'display_name', 'iqama_number', 'phone_number', 'avatar_url', 'last_login', 'birth_date']::TEXT[]) THEN
        RAISE EXCEPTION 'Only an administrator can change protected profile fields' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.protect_profile_privileged_fields() FROM PUBLIC;
CREATE TRIGGER protect_profile_privileged_fields_trigger
BEFORE UPDATE ON profiles FOR EACH ROW
EXECUTE FUNCTION public.protect_profile_privileged_fields();

-- 5. Payroll Table
CREATE TABLE payroll (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    month_year VARCHAR(20) NOT NULL,
    base_salary DECIMAL(10, 2) NOT NULL,
    overtime_pay DECIMAL(10, 2) DEFAULT 0,
    deductions DECIMAL(10, 2) DEFAULT 0,
    net_pay DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) DEFAULT 'PAID' CHECK (status IN ('PENDING', 'PAID')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE payroll ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees can view their own payroll" ON payroll FOR SELECT USING (auth.uid() = employee_id);
CREATE POLICY "Admins can view all payroll" ON payroll FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

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

-- 6. Performance Goals Table
CREATE TABLE performance_goals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    due_date DATE NOT NULL,
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'COMPLETED', 'OVERDUE')),
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE performance_goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees can view their own goals" ON performance_goals FOR SELECT USING (auth.uid() = employee_id);
CREATE POLICY "Admins can manage all goals" ON performance_goals USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- 7. Document Requests Table
CREATE TABLE document_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    doc_type VARCHAR(100) NOT NULL,
    purpose TEXT,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSED', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE document_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees can insert their own doc requests" ON document_requests FOR INSERT WITH CHECK (auth.uid() = employee_id);
CREATE POLICY "Employees can view their own doc requests" ON document_requests FOR SELECT USING (auth.uid() = employee_id);
CREATE POLICY "Admins can manage all doc requests" ON document_requests USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- ==========================================
-- ADMIN RPC: Create User By Admin
-- ==========================================
-- This function allows an admin to create a new user account securely via PostgreSQL
CREATE OR REPLACE FUNCTION create_user_by_admin(
    new_email TEXT,
    new_password TEXT,
    new_role VARCHAR(20) DEFAULT 'EMPLOYEE',
    new_job_title VARCHAR(100) DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_user_id UUID := gen_random_uuid();
    is_admin BOOLEAN;
BEGIN
    -- Check if the caller is an Admin
    SELECT EXISTS (
        SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'
    ) INTO is_admin;

    IF NOT is_admin THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can create users';
    END IF;

    -- Insert into auth.users using pgcrypto for the bcrypt password hash
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password, 
        email_confirmed_at, recovery_sent_at, last_sign_in_at, 
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
        confirmation_token, email_change, email_change_token_new, recovery_token
    )
    VALUES (
        '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated', new_email, 
        crypt(new_password, gen_salt('bf')), 
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

    -- Assign the role and job title in profiles table
    INSERT INTO public.profiles (id, role, job_title)
    VALUES (new_user_id, new_role, new_job_title);

    RETURN new_user_id;
END;
$$;

-- 8. Tasks Table (Teamwork Manager)
CREATE TABLE tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    assignee_id UUID REFERENCES auth.users(id),
    supervisor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    due_date DATE,
    status VARCHAR(20) DEFAULT 'TODO' CHECK (status IN ('TODO', 'IN_PROGRESS', 'DONE')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view tasks assigned to them" ON tasks FOR SELECT USING (auth.uid() = assignee_id OR auth.uid() = created_by OR auth.uid() = supervisor_id);
CREATE POLICY "Users can update their tasks" ON tasks FOR UPDATE USING (auth.uid() = assignee_id OR auth.uid() = created_by OR auth.uid() = supervisor_id);
CREATE POLICY "Admins have full access to tasks" ON tasks USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- 9. Employee Uploaded Documents
CREATE TABLE IF NOT EXISTS employee_documents (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    document_id BIGINT GENERATED BY DEFAULT AS IDENTITY UNIQUE,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    doc_name VARCHAR(255) NOT NULL,
    doc_type VARCHAR(50),
    doc_base64 TEXT,
    owner_name TEXT,
    owner_email TEXT,
    responsible_name TEXT,
    responsible_email TEXT,
    expiration_date DATE,
    notified_30_days BOOLEAN NOT NULL DEFAULT TRUE CHECK (notified_30_days = TRUE),
    owner_phone TEXT,
    status TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Expires Soon', 'Expired')),
    last_notification_status TEXT CHECK (last_notification_status IS NULL OR last_notification_status IN ('Expires Soon', 'Expired')),
    last_notified_at TIMESTAMP WITH TIME ZONE,
    last_notification_error TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE employee_documents ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.protect_employee_document_system_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND
       (to_jsonb(NEW) - ARRAY['doc_name', 'owner_name', 'owner_email', 'responsible_name', 'responsible_email', 'expiration_date', 'owner_phone']::TEXT[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['doc_name', 'owner_name', 'owner_email', 'responsible_name', 'responsible_email', 'expiration_date', 'owner_phone']::TEXT[]) THEN
        RAISE EXCEPTION 'System-managed document fields cannot be changed from the app' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.protect_employee_document_system_fields() FROM PUBLIC;
CREATE TRIGGER protect_employee_document_system_fields_trigger
BEFORE UPDATE ON employee_documents FOR EACH ROW
EXECUTE FUNCTION public.protect_employee_document_system_fields();
CREATE POLICY "Employees can view their own uploaded documents" ON employee_documents FOR SELECT USING (auth.uid() = employee_id);
CREATE POLICY "Employees can upload their own documents" ON employee_documents FOR INSERT WITH CHECK (auth.uid() = employee_id);
CREATE POLICY "Admins can view all uploaded documents" ON employee_documents FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));
CREATE POLICY "Authorized users can update employee documents" ON employee_documents FOR UPDATE
USING (
    auth.uid() = employee_id
    OR EXISTS (SELECT 1 FROM profiles caller WHERE caller.id = auth.uid() AND caller.role = 'ADMIN')
    OR EXISTS (
        SELECT 1 FROM profiles caller
        JOIN profiles document_owner ON document_owner.id = employee_documents.employee_id
        WHERE caller.id = auth.uid()
          AND caller.role IN ('MANAGER', 'SUPERVISOR')
          AND document_owner.manager_id = auth.uid()
    )
)
WITH CHECK (
    auth.uid() = employee_id
    OR EXISTS (SELECT 1 FROM profiles caller WHERE caller.id = auth.uid() AND caller.role = 'ADMIN')
    OR EXISTS (
        SELECT 1 FROM profiles caller
        JOIN profiles document_owner ON document_owner.id = employee_documents.employee_id
        WHERE caller.id = auth.uid()
          AND caller.role IN ('MANAGER', 'SUPERVISOR')
          AND document_owner.manager_id = auth.uid()
    )
);
CREATE POLICY "Authorized users can delete employee documents" ON employee_documents FOR DELETE
USING (
    auth.uid() = employee_id
    OR EXISTS (SELECT 1 FROM profiles caller WHERE caller.id = auth.uid() AND caller.role = 'ADMIN')
    OR EXISTS (
        SELECT 1 FROM profiles caller
        JOIN profiles document_owner ON document_owner.id = employee_documents.employee_id
        WHERE caller.id = auth.uid()
          AND caller.role IN ('MANAGER', 'SUPERVISOR')
          AND document_owner.manager_id = auth.uid()
    )
);

CREATE TABLE IF NOT EXISTS document_expiry_notifications (
    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    employee_document_id UUID NOT NULL REFERENCES employee_documents(id) ON DELETE CASCADE,
    notification_status TEXT NOT NULL CHECK (notification_status IN ('Expires Soon', 'Expired')),
    recipient_email TEXT NOT NULL,
    expiration_date DATE NOT NULL,
    days_left INTEGER NOT NULL,
    sent_at TIMESTAMP WITH TIME ZONE,
    provider_message_id TEXT,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (employee_document_id, notification_status, recipient_email, expiration_date)
);

ALTER TABLE document_expiry_notifications ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS admin_password_reset_audit (
    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    actor_user_id UUID NOT NULL,
    target_user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
ALTER TABLE admin_password_reset_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE admin_password_reset_audit FROM anon, authenticated;
CREATE INDEX admin_password_reset_audit_actor_created_idx ON admin_password_reset_audit(actor_user_id, created_at DESC);
CREATE INDEX admin_password_reset_audit_target_created_idx ON admin_password_reset_audit(target_user_id, created_at DESC);


-- 10. Expenses Table
CREATE TABLE IF NOT EXISTS expenses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    amount DECIMAL(10, 2) NOT NULL,
    description TEXT,
    receipt_base64 TEXT,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees can manage their own expenses" ON expenses FOR ALL USING (auth.uid() = employee_id);
CREATE POLICY "Admins/Managers can view and update all expenses" ON expenses FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));


-- 11. Notifications Table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own notifications" ON notifications FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Admins can insert notifications" ON notifications FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));
