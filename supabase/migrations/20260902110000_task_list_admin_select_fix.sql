-- Ensure admin/owner users can read the list row returned after creating or
-- editing a list, including lists assigned to another department.
BEGIN;
CREATE OR REPLACE FUNCTION public.can_view_task_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.task_lists list
    JOIN public.profiles viewer ON viewer.id = p_user_id
    WHERE list.id = p_list_id
      AND (
        list.owner_id = p_user_id
        OR UPPER(COALESCE(viewer.role, '')) IN ('ADMIN','OWNER','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
        OR list.department_id = viewer.department_id
        OR p_user_id = ANY(COALESCE(list.shared_with, '{}'::uuid[]))
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_view_task_list(uuid, uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
