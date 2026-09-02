-- Ensure every authenticated employee can create lists and tasks in lists
-- belonging to their own department. Sharing/access members remain limited to
-- that department; watcher visibility is handled by the existing directory RPC.
BEGIN;

ALTER TABLE public.task_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_lists TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;

CREATE OR REPLACE FUNCTION public.can_add_task_to_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.task_lists list
    JOIN public.profiles viewer ON viewer.id = p_user_id
    WHERE list.id = p_list_id
      AND (
        list.owner_id = p_user_id
        OR UPPER(COALESCE(viewer.role, '')) IN ('ADMIN','OWNER','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
        OR list.department_id = viewer.department_id
        OR p_user_id = ANY(COALESCE(list.can_add_users, '{}'::uuid[]))
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_task_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.task_lists list
    JOIN public.profiles viewer ON viewer.id = p_user_id
    WHERE list.id = p_list_id
      AND (
        list.owner_id = p_user_id
        OR list.department_id = viewer.department_id
        OR p_user_id = ANY(COALESCE(list.shared_with, '{}'::uuid[]))
      )
  );
$$;

DROP POLICY IF EXISTS task_lists_insert_owner ON public.task_lists;
CREATE POLICY task_lists_insert_owner ON public.task_lists
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS task_lists_select_department ON public.task_lists;
CREATE POLICY task_lists_select_department ON public.task_lists
  FOR SELECT TO authenticated
  USING (public.can_view_task_list(id, auth.uid()));

DROP POLICY IF EXISTS tasks_insert_own ON public.tasks;
CREATE POLICY tasks_insert_own ON public.tasks
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND (task_list_id IS NULL OR public.can_add_task_to_list(task_list_id, auth.uid()))
  );

GRANT EXECUTE ON FUNCTION public.can_view_task_list(uuid, uuid), public.can_add_task_to_list(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
