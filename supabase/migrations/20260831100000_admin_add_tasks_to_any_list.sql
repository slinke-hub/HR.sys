-- Administrators can create tasks in every task list.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_add_task_to_list(
  p_list_id UUID,
  p_user_id UUID DEFAULT auth.uid()
) RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.task_lists list
    JOIN public.profiles viewer ON viewer.id = p_user_id
    WHERE list.id = p_list_id
      AND (
        UPPER(COALESCE(viewer.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
        OR list.owner_id = p_user_id
        OR p_user_id = ANY(COALESCE(list.can_add_users, '{}'::UUID[]))
        OR (
          list.department_id IS NOT NULL
          AND viewer.department_id = list.department_id
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION public.can_add_task_to_list(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_add_task_to_list(UUID, UUID) TO authenticated;

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tasks_insert_own ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_authenticated_creator ON public.tasks;
CREATE POLICY tasks_insert_own
ON public.tasks FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND (
    task_list_id IS NULL
    OR public.can_add_task_to_list(task_list_id, auth.uid())
  )
);

NOTIFY pgrst, 'reload schema';
COMMIT;
