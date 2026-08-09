-- Fix for "fail to create tasks" bug

-- 1. Allow any authenticated user to create a task as long as they set themselves as the creator
CREATE POLICY "Users can create tasks" ON public.tasks
FOR INSERT 
WITH CHECK (auth.uid() = created_by);

-- Note: The existing policies for tasks are:
-- CREATE POLICY "Users can view tasks assigned to them" ON tasks FOR SELECT USING (auth.uid() = assignee_id OR auth.uid() = created_by);
-- CREATE POLICY "Users can update their tasks" ON tasks FOR UPDATE USING (auth.uid() = assignee_id OR auth.uid() = created_by);
-- CREATE POLICY "Admins have full access to tasks" ON tasks USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));
