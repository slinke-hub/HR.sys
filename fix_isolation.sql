-- Fix Data Isolation for Managers and Supervisors safely (skips missing tables)

-- 1. Profiles Table (Guaranteed to exist)
DROP POLICY IF EXISTS "Admins and Managers can read profiles" ON profiles;
DROP POLICY IF EXISTS "Admins can read all profiles" ON profiles;

CREATE POLICY "Admins can read all profiles" ON profiles 
FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN')
);

CREATE POLICY "Managers can read team profiles" ON profiles 
FOR SELECT USING (
    manager_id = auth.uid() OR id = auth.uid()
);

-- For the rest of the tables, we use dynamic SQL to safely apply policies only if the tables exist.
DO $$
BEGIN
    -- 2. Attendance Table
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'attendance') THEN
        DROP POLICY IF EXISTS "Admins/Managers can view all attendance" ON public.attendance;
        EXECUTE 'CREATE POLICY "Admins can view all attendance" ON public.attendance FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ''ADMIN''))';
        EXECUTE 'CREATE POLICY "Managers can view team attendance" ON public.attendance FOR SELECT USING (employee_id IN (SELECT id FROM profiles WHERE manager_id = auth.uid()))';
    END IF;

    -- 3. Leave Requests
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'leave_requests') THEN
        DROP POLICY IF EXISTS "Admins can update leave requests" ON public.leave_requests;
        DROP POLICY IF EXISTS "Admins and Managers can update leave requests" ON public.leave_requests;
        EXECUTE 'CREATE POLICY "Admins can manage leave requests" ON public.leave_requests FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ''ADMIN''))';
        EXECUTE 'CREATE POLICY "Managers can view team leave requests" ON public.leave_requests FOR SELECT USING (employee_id IN (SELECT id FROM profiles WHERE manager_id = auth.uid()))';
        EXECUTE 'CREATE POLICY "Managers can update team leave requests" ON public.leave_requests FOR UPDATE USING (employee_id IN (SELECT id FROM profiles WHERE manager_id = auth.uid()))';
    END IF;

    -- 4. Expenses
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'expenses') THEN
        DROP POLICY IF EXISTS "Admins/Managers can view and update all expenses" ON public.expenses;
        EXECUTE 'CREATE POLICY "Admins can view and update all expenses" ON public.expenses FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ''ADMIN''))';
        EXECUTE 'CREATE POLICY "Managers can view and update team expenses" ON public.expenses FOR ALL USING (employee_id IN (SELECT id FROM profiles WHERE manager_id = auth.uid()))';
    END IF;

    -- 5. Employee Documents
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'employee_documents') THEN
        DROP POLICY IF EXISTS "Admins can view all uploaded documents" ON public.employee_documents;
        EXECUTE 'CREATE POLICY "Admins can view all uploaded documents" ON public.employee_documents FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ''ADMIN''))';
        EXECUTE 'CREATE POLICY "Managers can view team documents" ON public.employee_documents FOR SELECT USING (employee_id IN (SELECT id FROM profiles WHERE manager_id = auth.uid()))';
    END IF;

    -- 6. Performance Goals
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'performance_goals') THEN
        DROP POLICY IF EXISTS "Admins can manage all goals" ON public.performance_goals;
        EXECUTE 'CREATE POLICY "Admins can manage all goals" ON public.performance_goals FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ''ADMIN''))';
        EXECUTE 'CREATE POLICY "Managers can manage team goals" ON public.performance_goals FOR ALL USING (employee_id IN (SELECT id FROM profiles WHERE manager_id = auth.uid()))';
    END IF;

    -- 7. Document Requests
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'document_requests') THEN
        DROP POLICY IF EXISTS "Admins can manage all doc requests" ON public.document_requests;
        EXECUTE 'CREATE POLICY "Admins can manage all doc requests" ON public.document_requests FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ''ADMIN''))';
        EXECUTE 'CREATE POLICY "Managers can manage team doc requests" ON public.document_requests FOR ALL USING (employee_id IN (SELECT id FROM profiles WHERE manager_id = auth.uid()))';
    END IF;

    -- 8. Payroll
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'payroll') THEN
        DROP POLICY IF EXISTS "Admins can view all payroll" ON public.payroll;
        EXECUTE 'CREATE POLICY "Admins can view all payroll" ON public.payroll FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = ''ADMIN''))';
        EXECUTE 'CREATE POLICY "Managers can view team payroll" ON public.payroll FOR SELECT USING (employee_id IN (SELECT id FROM profiles WHERE manager_id = auth.uid()))';
    END IF;
END $$;
