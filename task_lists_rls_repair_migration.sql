-- Repair task-list permissions for authenticated employees.
-- Run this in Supabase SQL Editor if creating a private list returns HTTP 403.

ALTER TABLE public.task_lists ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_lists TO authenticated;

DROP POLICY IF EXISTS task_lists_select_owner_or_viewer ON public.task_lists;
CREATE POLICY task_lists_select_owner_or_viewer ON public.task_lists
FOR SELECT TO authenticated
USING (
  owner_id = auth.uid()
  OR auth.uid() = ANY(COALESCE(shared_with, '{}'::uuid[]))
);

DROP POLICY IF EXISTS task_lists_insert_owner ON public.task_lists;
CREATE POLICY task_lists_insert_owner ON public.task_lists
FOR INSERT TO authenticated
WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS task_lists_update_owner ON public.task_lists;
CREATE POLICY task_lists_update_owner ON public.task_lists
FOR UPDATE TO authenticated
USING (owner_id = auth.uid())
WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS task_lists_delete_owner ON public.task_lists;
CREATE POLICY task_lists_delete_owner ON public.task_lists
FOR DELETE TO authenticated
USING (owner_id = auth.uid());

NOTIFY pgrst, 'reload schema';
