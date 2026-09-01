-- Repair task and task-list permissions for all authenticated employees.
-- List membership remains department-scoped; task watchers may come from the
-- whole active company directory.
BEGIN;

ALTER TABLE public.task_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_lists
  ADD COLUMN IF NOT EXISTS department_id uuid REFERENCES public.departments(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS visible_to_all boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_add_users uuid[] NOT NULL DEFAULT '{}'::uuid[],
  ADD COLUMN IF NOT EXISTS can_delete_users uuid[] NOT NULL DEFAULT '{}'::uuid[],
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS template text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS notify_assignee boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS notify_complete boolean NOT NULL DEFAULT false;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_lists TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_task_list_department_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  owner_department uuid;
  invalid_member uuid;
BEGIN
  SELECT department_id INTO owner_department
  FROM public.profiles
  WHERE id = NEW.owner_id;

  IF owner_department IS NULL THEN
    RAISE EXCEPTION 'A department must be assigned before creating a task list'
      USING ERRCODE = '23514';
  END IF;

  NEW.department_id := owner_department;
  NEW.visible_to_all := false;
  NEW.shared_with := array_remove(COALESCE(NEW.shared_with, '{}'::uuid[]), NEW.owner_id);
  NEW.can_add_users := array_remove(COALESCE(NEW.can_add_users, '{}'::uuid[]), NEW.owner_id);
  NEW.can_delete_users := array_remove(COALESCE(NEW.can_delete_users, '{}'::uuid[]), NEW.owner_id);

  SELECT member_id INTO invalid_member
  FROM unnest(NEW.shared_with || NEW.can_add_users || NEW.can_delete_users) AS member_id
  LEFT JOIN public.profiles member ON member.id = member_id
  WHERE member.id IS NULL OR member.department_id IS DISTINCT FROM owner_department
  LIMIT 1;

  IF invalid_member IS NOT NULL THEN
    RAISE EXCEPTION 'Task-list access can only be granted to employees in the owner''s department'
      USING ERRCODE = '42501';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_task_list_sharing_trigger ON public.task_lists;
DROP TRIGGER IF EXISTS validate_task_list_department_visibility_trigger ON public.task_lists;
DROP TRIGGER IF EXISTS validate_task_list_department_access_trigger ON public.task_lists;
CREATE TRIGGER validate_task_list_department_access_trigger
BEFORE INSERT OR UPDATE OF owner_id, department_id, visible_to_all, shared_with, can_add_users, can_delete_users
ON public.task_lists
FOR EACH ROW EXECUTE FUNCTION public.validate_task_list_department_access();

CREATE OR REPLACE FUNCTION public.can_view_task_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.task_lists list
    JOIN public.profiles viewer ON viewer.id = p_user_id
    WHERE list.id = p_list_id
      AND (list.owner_id = p_user_id OR list.department_id = viewer.department_id
           OR p_user_id = ANY(COALESCE(list.shared_with, '{}'::uuid[])))
  );
$$;

CREATE OR REPLACE FUNCTION public.can_add_task_to_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.task_lists list
    JOIN public.profiles viewer ON viewer.id = p_user_id
    WHERE list.id = p_list_id
      AND (list.owner_id = p_user_id
           OR UPPER(COALESCE(viewer.role, '')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
           OR list.department_id = viewer.department_id
           OR p_user_id = ANY(COALESCE(list.can_add_users, '{}'::uuid[])))
  );
$$;

DROP POLICY IF EXISTS task_lists_select_owner_or_viewer ON public.task_lists;
DROP POLICY IF EXISTS task_lists_select_department ON public.task_lists;
CREATE POLICY task_lists_select_department ON public.task_lists FOR SELECT TO authenticated
USING (public.can_view_task_list(id, auth.uid()));

DROP POLICY IF EXISTS task_lists_insert_owner ON public.task_lists;
CREATE POLICY task_lists_insert_owner ON public.task_lists FOR INSERT TO authenticated
WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS task_lists_update_owner ON public.task_lists;
CREATE POLICY task_lists_update_owner ON public.task_lists FOR UPDATE TO authenticated
USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS task_lists_delete_owner ON public.task_lists;
CREATE POLICY task_lists_delete_owner ON public.task_lists FOR DELETE TO authenticated
USING (owner_id = auth.uid());

DROP POLICY IF EXISTS tasks_insert_authenticated_creator ON public.tasks;
DROP POLICY IF EXISTS tasks_insert_own ON public.tasks;
CREATE POLICY tasks_insert_own ON public.tasks FOR INSERT TO authenticated
WITH CHECK (created_by = auth.uid() AND (task_list_id IS NULL OR public.can_add_task_to_list(task_list_id, auth.uid())));

CREATE OR REPLACE FUNCTION public.enforce_private_task_list_ownership()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
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

CREATE OR REPLACE FUNCTION public.validate_task_department_supervisor()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE expected_supervisor_id uuid; caller_role text;
BEGIN
  IF NEW.task_list_id IS NOT NULL THEN RETURN NEW; END IF;
  SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
  IF UPPER(COALESCE(caller_role, '')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN') THEN RETURN NEW; END IF;
  SELECT department.head_id INTO expected_supervisor_id
  FROM public.profiles creator LEFT JOIN public.departments department ON department.id = creator.department_id
  WHERE creator.id = NEW.created_by;
  IF NEW.supervisor_id IS DISTINCT FROM expected_supervisor_id THEN
    RAISE EXCEPTION 'Selected supervisor must be the task creator''s department manager' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_task_watcher_directory()
RETURNS TABLE(id uuid, full_name text, display_name_ar text, role text, department_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT profile.id, profile.full_name::text, profile.display_name_ar::text,
         profile.role::text, profile.department_id
  FROM public.profiles profile
  WHERE profile.is_active IS DISTINCT FROM false
  ORDER BY profile.full_name;
$$;

CREATE OR REPLACE FUNCTION public.get_task_list_department_directory()
RETURNS TABLE(id uuid, full_name text, display_name_ar text, role text, department_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT member.id, member.full_name::text, member.display_name_ar::text,
         member.role::text, member.department_id
  FROM public.profiles viewer
  JOIN public.profiles member ON member.department_id = viewer.department_id
  WHERE viewer.id = auth.uid()
    AND member.is_active IS DISTINCT FROM false
  ORDER BY member.full_name;
$$;

REVOKE ALL ON FUNCTION public.get_task_watcher_directory() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_task_watcher_directory() TO authenticated;
REVOKE ALL ON FUNCTION public.get_task_list_department_directory() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_task_list_department_directory() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_task_list(uuid, uuid), public.can_add_task_to_list(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
