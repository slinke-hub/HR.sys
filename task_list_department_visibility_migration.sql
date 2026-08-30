-- Department-scoped visibility for Task Manager lists.
-- Employees can only read lists assigned to their own department.

BEGIN;

ALTER TABLE public.task_lists
  ADD COLUMN IF NOT EXISTS department_id uuid REFERENCES public.departments(id) ON DELETE SET NULL;

ALTER TABLE public.task_lists
  ADD COLUMN IF NOT EXISTS visible_to_all boolean NOT NULL DEFAULT false;

ALTER TABLE public.task_lists
  ADD COLUMN IF NOT EXISTS can_add_users uuid[] NOT NULL DEFAULT '{}'::uuid[],
  ADD COLUMN IF NOT EXISTS can_delete_users uuid[] NOT NULL DEFAULT '{}'::uuid[],
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS template text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS notify_assignee boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS notify_complete boolean NOT NULL DEFAULT false;

UPDATE public.task_lists list
SET department_id = owner.department_id
FROM public.profiles owner
WHERE owner.id = list.owner_id
  AND list.department_id IS NULL;

CREATE INDEX IF NOT EXISTS task_lists_department_id_idx
  ON public.task_lists(department_id);

CREATE OR REPLACE FUNCTION public.validate_task_list_department_visibility()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  owner_department uuid;
  actor_is_admin boolean := false;
  invalid_viewer uuid;
BEGIN
  SELECT department_id INTO owner_department
  FROM public.profiles
  WHERE id = NEW.owner_id;

  SELECT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id = auth.uid()
      AND upper(coalesce(profile.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
  ) INTO actor_is_admin;

  IF NEW.visible_to_all AND NOT actor_is_admin THEN
    RAISE EXCEPTION 'Only administrators can make a task list visible to all departments'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.visible_to_all THEN
    NEW.department_id := NULL;
  ELSE
    NEW.department_id := coalesce(NEW.department_id, owner_department);
  END IF;

  IF NOT actor_is_admin AND NOT NEW.visible_to_all AND NEW.department_id IS DISTINCT FROM owner_department THEN
    RAISE EXCEPTION 'Employees can only create task lists for their own department'
      USING ERRCODE = '42501';
  END IF;

  NEW.shared_with := array_remove(coalesce(NEW.shared_with, '{}'::uuid[]), NEW.owner_id);

  SELECT viewer_id INTO invalid_viewer
  FROM unnest(NEW.shared_with) viewer_id
  LEFT JOIN public.profiles viewer ON viewer.id = viewer_id
  WHERE viewer.id IS NULL OR (NOT NEW.visible_to_all AND viewer.department_id IS DISTINCT FROM NEW.department_id)
  LIMIT 1;

  IF invalid_viewer IS NOT NULL THEN
    RAISE EXCEPTION 'A task list can only be shared with employees in its department'
      USING ERRCODE = '42501';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_task_list_department_visibility_trigger ON public.task_lists;
-- The department-aware trigger supersedes the older same-department sharing
-- trigger, which otherwise rejects the explicit "All employees" choice.
DROP TRIGGER IF EXISTS validate_task_list_sharing_trigger ON public.task_lists;
CREATE TRIGGER validate_task_list_department_visibility_trigger
BEFORE INSERT OR UPDATE OF owner_id, department_id, visible_to_all, shared_with
ON public.task_lists
FOR EACH ROW EXECUTE FUNCTION public.validate_task_list_department_visibility();

CREATE OR REPLACE FUNCTION public.can_view_task_list(
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
        upper(coalesce(viewer.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
        OR list.owner_id = p_user_id
        OR list.visible_to_all
        OR (
          list.department_id IS NOT NULL
          AND viewer.department_id = list.department_id
        )
      )
  );
$$;

ALTER TABLE public.task_lists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_lists_select_owner_or_viewer ON public.task_lists;
DROP POLICY IF EXISTS task_lists_select_department ON public.task_lists;
CREATE POLICY task_lists_select_department
ON public.task_lists
FOR SELECT TO authenticated
USING (public.can_view_task_list(id, auth.uid()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_lists TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_task_list(uuid, uuid) TO authenticated;

-- Allow employees explicitly granted delete permission on a task list to
-- delete tasks in that list.  The UI stores the selected employee UUIDs in
-- can_delete_users (including every UUID when "All employees" is selected).
CREATE OR REPLACE FUNCTION public.can_delete_task(
  p_task_id uuid,
  p_user_id uuid DEFAULT auth.uid()
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tasks task
    LEFT JOIN public.task_lists list ON list.id = task.task_list_id
    WHERE task.id = p_task_id
      AND (
        task.created_by = p_user_id
        OR public.is_task_admin(p_user_id)
        OR p_user_id = ANY(COALESCE(list.can_delete_users, '{}'::uuid[]))
      )
  );
$$;

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tasks_delete_creator_or_admin ON public.tasks;
DROP POLICY IF EXISTS tasks_delete_authorized ON public.tasks;
CREATE POLICY tasks_delete_authorized
ON public.tasks FOR DELETE TO authenticated
USING (public.can_delete_task(id, auth.uid()));

GRANT EXECUTE ON FUNCTION public.can_delete_task(uuid, uuid) TO authenticated;

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
    SELECT 1 FROM public.task_lists list
    WHERE list.id = p_list_id
      AND (
        list.owner_id = p_user_id
        OR public.is_task_admin(p_user_id)
        OR p_user_id = ANY(COALESCE(list.can_add_users, '{}'::uuid[]))
      )
  );
$$;

DROP POLICY IF EXISTS tasks_insert_own ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_authenticated_creator ON public.tasks;
CREATE POLICY tasks_insert_own
ON public.tasks FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  AND (task_list_id IS NULL OR public.can_add_task_to_list(task_list_id, auth.uid()))
);

GRANT EXECUTE ON FUNCTION public.can_add_task_to_list(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
