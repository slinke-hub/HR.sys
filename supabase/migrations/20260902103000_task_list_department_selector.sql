-- Let admins/owners choose the department visible in a task list. Other roles
-- remain restricted to their own department.
BEGIN;
CREATE OR REPLACE FUNCTION public.validate_task_list_department_access()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE owner_department uuid; caller_role text; invalid_member uuid;
BEGIN
  SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
  SELECT department_id INTO owner_department FROM public.profiles WHERE id = NEW.owner_id;
  IF owner_department IS NULL THEN RAISE EXCEPTION 'A department must be assigned before creating a task list' USING ERRCODE = '23514'; END IF;
  IF UPPER(COALESCE(caller_role, '')) NOT IN ('ADMIN','OWNER','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN') OR NEW.department_id IS NULL THEN NEW.department_id := owner_department; END IF;
  NEW.visible_to_all := false;
  NEW.shared_with := array_remove(COALESCE(NEW.shared_with, '{}'::uuid[]), NEW.owner_id);
  NEW.can_add_users := array_remove(COALESCE(NEW.can_add_users, '{}'::uuid[]), NEW.owner_id);
  NEW.can_delete_users := array_remove(COALESCE(NEW.can_delete_users, '{}'::uuid[]), NEW.owner_id);
  SELECT member_id INTO invalid_member FROM unnest(NEW.shared_with || NEW.can_add_users || NEW.can_delete_users) AS member_id LEFT JOIN public.profiles member ON member.id = member_id WHERE member.id IS NULL OR member.department_id IS DISTINCT FROM NEW.department_id LIMIT 1;
  IF invalid_member IS NOT NULL THEN RAISE EXCEPTION 'Task-list access can only be granted to employees in the selected department' USING ERRCODE = '42501'; END IF;
  NEW.updated_at := now(); RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS validate_task_list_department_access_trigger ON public.task_lists;
CREATE TRIGGER validate_task_list_department_access_trigger BEFORE INSERT OR UPDATE OF owner_id, department_id, visible_to_all, shared_with, can_add_users, can_delete_users ON public.task_lists FOR EACH ROW EXECUTE FUNCTION public.validate_task_list_department_access();
NOTIFY pgrst, 'reload schema';
COMMIT;
