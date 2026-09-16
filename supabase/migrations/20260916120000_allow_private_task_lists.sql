BEGIN;

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
  END IF;

  IF NOT actor_is_admin AND NOT NEW.visible_to_all AND NEW.department_id IS NOT NULL AND NEW.department_id IS DISTINCT FROM owner_department THEN
    RAISE EXCEPTION 'Employees can only create task lists for their own department'
      USING ERRCODE = '42501';
  END IF;

  NEW.shared_with := array_remove(coalesce(NEW.shared_with, '{}'::uuid[]), NEW.owner_id);

  SELECT viewer_id INTO invalid_viewer
  FROM unnest(NEW.shared_with) viewer_id
  LEFT JOIN public.profiles viewer ON viewer.id = viewer_id
  WHERE viewer.id IS NULL OR (NOT NEW.visible_to_all AND NEW.department_id IS NOT NULL AND viewer.department_id IS DISTINCT FROM NEW.department_id)
  LIMIT 1;

  IF invalid_viewer IS NOT NULL THEN
    RAISE EXCEPTION 'A task list can only be shared with employees in its department'
      USING ERRCODE = '42501';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_task_list_for_user(
  p_name text,
  p_shared_with uuid[] DEFAULT '{}'::uuid[],
  p_department_id uuid DEFAULT NULL,
  p_visible_to_all boolean DEFAULT false,
  p_can_add_users uuid[] DEFAULT '{}'::uuid[],
  p_can_delete_users uuid[] DEFAULT '{}'::uuid[],
  p_description text DEFAULT NULL,
  p_template text DEFAULT 'none',
  p_notify_assignee boolean DEFAULT false,
  p_notify_complete boolean DEFAULT false
)
RETURNS public.task_lists
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE caller_id uuid := auth.uid(); caller_role text; own_department uuid; target_department uuid; result_row public.task_lists;
BEGIN
  IF caller_id IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT role, department_id INTO caller_role, own_department FROM public.profiles WHERE id = caller_id;
  IF own_department IS NULL THEN RAISE EXCEPTION 'A department must be assigned before creating a task list' USING ERRCODE = '23514'; END IF;
  
  target_department := p_department_id;
  IF target_department IS NOT NULL AND target_department IS DISTINCT FROM own_department THEN
    IF UPPER(COALESCE(caller_role, '')) NOT IN ('ADMIN','OWNER','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN') THEN
       target_department := own_department;
    END IF;
  END IF;

  IF target_department IS NOT NULL THEN
      IF EXISTS (SELECT 1 FROM unnest(COALESCE(p_shared_with, '{}'::uuid[]) || COALESCE(p_can_add_users, '{}'::uuid[]) || COALESCE(p_can_delete_users, '{}'::uuid[])) member_id LEFT JOIN public.profiles member ON member.id = member_id WHERE member.id IS NULL OR member.department_id IS DISTINCT FROM target_department) THEN
        RAISE EXCEPTION 'Task-list access can only be granted to employees in the selected department' USING ERRCODE = '42501';
      END IF;
  END IF;

  INSERT INTO public.task_lists(name, owner_id, shared_with, department_id, visible_to_all, can_add_users, can_delete_users, description, template, notify_assignee, notify_complete)
  VALUES (trim(p_name), caller_id, COALESCE(p_shared_with, '{}'::uuid[]), target_department, false, COALESCE(p_can_add_users, '{}'::uuid[]), COALESCE(p_can_delete_users, '{}'::uuid[]), p_description, COALESCE(p_template, 'none'), COALESCE(p_notify_assignee, false), COALESCE(p_notify_complete, false))
  RETURNING * INTO result_row;
  RETURN result_row;
END; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
