-- Policies to allow Managers to view and manage data for their direct reports

-- Note: We use auth.uid() to match the 'manager_id' in profiles.
-- We must drop the existing specific policies if we want to replace them, but we can also just ADD new policies since they are additive (OR).

-- 1. Tasks
DROP POLICY IF EXISTS "Managers can view team tasks" ON public.tasks;
CREATE POLICY "Managers can view team tasks" ON public.tasks 
    FOR SELECT USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = tasks.assignee_id)
    );
DROP POLICY IF EXISTS "Managers can update team tasks" ON public.tasks;
CREATE POLICY "Managers can update team tasks" ON public.tasks 
    FOR UPDATE USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = tasks.assignee_id)
    );

-- 2. Leave Requests
DROP POLICY IF EXISTS "Managers can view team leave requests" ON public.leave_requests;
CREATE POLICY "Managers can view team leave requests" ON public.leave_requests 
    FOR SELECT USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = leave_requests.employee_id)
    );

-- 3. Document Requests
DROP POLICY IF EXISTS "Managers can view team document requests" ON public.document_requests;
CREATE POLICY "Managers can view team document requests" ON public.document_requests 
    FOR SELECT USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = document_requests.employee_id)
    );

-- 4. Employee Documents (uploaded by team)
DROP POLICY IF EXISTS "Managers can view team documents" ON public.employee_documents;
CREATE POLICY "Managers can view team documents" ON public.employee_documents 
    FOR SELECT USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = employee_documents.employee_id)
    );

-- 5. Performance Goals
DROP POLICY IF EXISTS "Managers can view team goals" ON public.performance_goals;
CREATE POLICY "Managers can view team goals" ON public.performance_goals 
    FOR SELECT USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = performance_goals.employee_id)
    );
DROP POLICY IF EXISTS "Managers can update team goals" ON public.performance_goals;
CREATE POLICY "Managers can update team goals" ON public.performance_goals 
    FOR UPDATE USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = performance_goals.employee_id)
    );
DROP POLICY IF EXISTS "Managers can insert team goals" ON public.performance_goals;
CREATE POLICY "Managers can insert team goals" ON public.performance_goals 
    FOR INSERT WITH CHECK (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = employee_id)
    );
DROP POLICY IF EXISTS "Managers can delete team goals" ON public.performance_goals;
CREATE POLICY "Managers can delete team goals" ON public.performance_goals 
    FOR DELETE USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = performance_goals.employee_id)
    );

-- 6. Expenses (Already handled in schema.sql: "Admins/Managers can view and update all expenses")
-- "Admins/Managers can view and update all expenses" was already created, but if we want to restrict it ONLY to their team:
-- We can leave it as is if company policy allows managers to see all expenses, or we could drop and recreate. 
-- Since the user specified "own tasks, Team members", we should drop the global manager policy for expenses and scope it to team.
DROP POLICY IF EXISTS "Admins/Managers can view and update all expenses" ON public.expenses;

DROP POLICY IF EXISTS "Admins can view and update all expenses" ON public.expenses;
CREATE POLICY "Admins can view and update all expenses" ON public.expenses 
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN')
    );

DROP POLICY IF EXISTS "Managers can manage team expenses" ON public.expenses;
CREATE POLICY "Managers can manage team expenses" ON public.expenses 
    FOR ALL USING (
        auth.uid() IN (SELECT manager_id FROM public.profiles WHERE id = expenses.employee_id)
    );
