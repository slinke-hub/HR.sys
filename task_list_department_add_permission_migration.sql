-- Allow every employee to add tasks to a task list assigned to their own department.
-- Explicit can_add_users permissions and administrator/owner access remain supported.

BEGIN;

CREATE OR REPLACE FUNCTION public.can_add_task_to_list(
  p_list_id uuid,
  p_user_id uuid DEFAULT auth.uid()
) RETURNS boolean
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
        list.owner_id = p_user_id
        OR public.is_task_admin(p_user_id)
        OR p_user_id = ANY(COALESCE(list.can_add_users, '{}'::uuid[]))
        OR (
          list.department_id IS NOT NULL
          AND viewer.department_id = list.department_id
        )
      )
  );
$$;

GRANT EXECUTE ON FUNCTION public.can_add_task_to_list(uuid, uuid) TO authenticated;

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
