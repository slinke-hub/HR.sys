-- 1. Alter Profiles (if columns don't exist)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS manager_id UUID REFERENCES auth.users(id);
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS base_salary DECIMAL(10, 2) DEFAULT 3000.00;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS annual_leave_allowance INTEGER DEFAULT 30;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS sick_leave_allowance INTEGER DEFAULT 10;

-- 2. Performance Goals Table
CREATE TABLE IF NOT EXISTS performance_goals (
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
DROP POLICY IF EXISTS "Employees can view their own goals" ON performance_goals;
CREATE POLICY "Employees can view their own goals" ON performance_goals FOR SELECT USING (auth.uid() = employee_id);
DROP POLICY IF EXISTS "Admins can manage all goals" ON performance_goals;
CREATE POLICY "Admins can manage all goals" ON performance_goals USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- 3. Document Requests Table
CREATE TABLE IF NOT EXISTS document_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    doc_type VARCHAR(100) NOT NULL,
    purpose TEXT,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSED', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE document_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Employees can insert their own doc requests" ON document_requests;
CREATE POLICY "Employees can insert their own doc requests" ON document_requests FOR INSERT WITH CHECK (auth.uid() = employee_id);
DROP POLICY IF EXISTS "Employees can view their own doc requests" ON document_requests;
CREATE POLICY "Employees can view their own doc requests" ON document_requests FOR SELECT USING (auth.uid() = employee_id);
DROP POLICY IF EXISTS "Admins can manage all doc requests" ON document_requests;
CREATE POLICY "Admins can manage all doc requests" ON document_requests USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- 4. Tasks Table
CREATE TABLE IF NOT EXISTS tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    assignee_id UUID REFERENCES auth.users(id),
    created_by UUID NOT NULL REFERENCES auth.users(id),
    due_date DATE,
    status VARCHAR(20) DEFAULT 'TODO' CHECK (status IN ('TODO', 'IN_PROGRESS', 'DONE')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view tasks assigned to them" ON tasks;
CREATE POLICY "Users can view tasks assigned to them" ON tasks FOR SELECT USING (auth.uid() = assignee_id OR auth.uid() = created_by);
DROP POLICY IF EXISTS "Users can update their tasks" ON tasks;
CREATE POLICY "Users can update their tasks" ON tasks FOR UPDATE USING (auth.uid() = assignee_id OR auth.uid() = created_by);
DROP POLICY IF EXISTS "Admins have full access to tasks" ON tasks;
CREATE POLICY "Admins have full access to tasks" ON tasks USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- 5. Employee Documents Table
CREATE TABLE IF NOT EXISTS employee_documents (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    doc_name VARCHAR(255) NOT NULL,
    doc_type VARCHAR(50) NOT NULL,
    doc_base64 TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE employee_documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Employees can view their own uploaded documents" ON employee_documents;
CREATE POLICY "Employees can view their own uploaded documents" ON employee_documents FOR SELECT USING (auth.uid() = employee_id);
DROP POLICY IF EXISTS "Employees can upload their own documents" ON employee_documents;
CREATE POLICY "Employees can upload their own documents" ON employee_documents FOR INSERT WITH CHECK (auth.uid() = employee_id);
DROP POLICY IF EXISTS "Admins can view all uploaded documents" ON employee_documents;
CREATE POLICY "Admins can view all uploaded documents" ON employee_documents FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));

-- 6. Expenses Table
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
DROP POLICY IF EXISTS "Employees can manage their own expenses" ON expenses;
CREATE POLICY "Employees can manage their own expenses" ON expenses FOR ALL USING (auth.uid() = employee_id);
DROP POLICY IF EXISTS "Admins/Managers can view and update all expenses" ON expenses;
CREATE POLICY "Admins/Managers can view and update all expenses" ON expenses FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));

-- 7. Notifications Table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own notifications" ON notifications;
CREATE POLICY "Users can manage their own notifications" ON notifications FOR ALL USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Admins can insert notifications" ON notifications;
CREATE POLICY "Admins can insert notifications" ON notifications FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));

-- 8. Create User By Admin Function
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
    SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN') INTO is_admin;
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can create users';
    END IF;

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

    INSERT INTO auth.identities (
        provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
    )
    VALUES (
        new_user_id::text, new_user_id, format('{"sub":"%s","email":"%s"}', new_user_id::text, new_email)::jsonb, 'email', now(), now(), now(), gen_random_uuid()
    );

    INSERT INTO public.profiles (id, role, job_title)
    VALUES (new_user_id, new_role, new_job_title);

    RETURN new_user_id;
END;
$$;
