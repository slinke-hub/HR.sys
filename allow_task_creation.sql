-- Allow all users to insert tasks where they are the creator
CREATE POLICY "Users can create tasks" ON public.tasks FOR INSERT WITH CHECK (auth.uid() = created_by);
