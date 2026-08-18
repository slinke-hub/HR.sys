-- Adds new columns for the Marketing approval workflow and watcher functionality
ALTER TABLE public.tasks 
ADD COLUMN IF NOT EXISTS department VARCHAR(255),
ADD COLUMN IF NOT EXISTS sub_type VARCHAR(255),
ADD COLUMN IF NOT EXISTS watchers UUID[] DEFAULT '{}';

-- Allow users who are added as watchers to view the tasks
CREATE POLICY "Watchers can view tasks" ON public.tasks FOR SELECT USING (auth.uid() = ANY(watchers));
