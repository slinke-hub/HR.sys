-- Repair HTTP 403 when an authenticated employee creates a task.
-- This policy intentionally requires the creator to be the signed-in user;
-- existing SELECT/UPDATE policies continue to control visibility and editing.

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;

DROP POLICY IF EXISTS tasks_insert_authenticated_creator ON public.tasks;
CREATE POLICY tasks_insert_authenticated_creator
ON public.tasks FOR INSERT TO authenticated
WITH CHECK (created_by = auth.uid());

NOTIFY pgrst, 'reload schema';
