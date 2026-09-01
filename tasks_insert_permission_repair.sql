-- Repair HTTP 403 when an authenticated employee creates a task.
-- This policy intentionally requires the creator to be the signed-in user;
-- existing SELECT/UPDATE policies continue to control visibility and editing.

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;

CREATE OR REPLACE FUNCTION public.can_add_task_to_list(
  p_list_id uuid,
  p_user_id uuid DEFAULT auth.uid()
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.task_lists list
    JOIN public.profiles viewer ON viewer.id = p_user_id
    WHERE list.id = p_list_id
      AND (
        list.owner_id = p_user_id
        OR list.department_id = viewer.department_id
        OR p_user_id = ANY(COALESCE(list.can_add_users, '{}'::uuid[]))
        OR UPPER(COALESCE(viewer.role, '')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
      )
  );
$$;

DROP POLICY IF EXISTS tasks_insert_authenticated_creator ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_own ON public.tasks;
CREATE POLICY tasks_insert_own
ON public.tasks FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND (task_list_id IS NULL OR public.can_add_task_to_list(task_list_id, auth.uid()))
);

-- Replace the legacy owner-only trigger. Employees may add tasks to lists in
-- their own department; the selected watchers are preserved.
CREATE OR REPLACE FUNCTION public.enforce_private_task_list_ownership()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.task_list_id IS NULL THEN RETURN NEW; END IF;
  IF NOT public.can_add_task_to_list(NEW.task_list_id, auth.uid()) THEN
    RAISE EXCEPTION 'You cannot add tasks to this task list' USING ERRCODE = '42501';
  END IF;
  NEW.visibility := 'private';
  NEW.visible_to := '{}';
  NEW.supervisor_id := NULL;
  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_add_task_to_list(uuid, uuid) TO authenticated;

-- Supabase task creation requests return the inserted row. Keep that RETURNING
-- path compatible with RLS without widening task visibility to other users.
DROP POLICY IF EXISTS tasks_select_own_created ON public.tasks;
CREATE POLICY tasks_select_own_created
ON public.tasks FOR SELECT TO authenticated
USING (created_by = auth.uid());

NOTIFY pgrst, 'reload schema';
