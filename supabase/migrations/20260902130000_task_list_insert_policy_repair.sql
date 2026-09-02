-- Remove legacy/conflicting INSERT policies and leave one explicit policy for
-- authenticated users creating their own task lists.
BEGIN;
DO $$
DECLARE p record;
BEGIN
  FOR p IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'task_lists' AND cmd = 'INSERT'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.task_lists', p.policyname);
  END LOOP;
END $$;

CREATE POLICY task_lists_insert_authenticated_owner ON public.task_lists
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());

GRANT INSERT ON public.task_lists TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
