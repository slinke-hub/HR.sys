-- Give administrators, CEOs, and GMs company-wide task assignment access.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_assign_tasks_company_wide(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'
              )
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.job_title, ''), '[_-]+', ' ', 'g'))) IN (
                  'GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
              )
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_assign_tasks_company_wide(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_assign_tasks_company_wide(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_add_task_to_list(p_list_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT public.can_assign_tasks_company_wide(p_user_id)
        OR EXISTS (
            SELECT 1
            FROM public.task_lists list
            JOIN public.profiles viewer ON viewer.id = p_user_id
            WHERE list.id = p_list_id
              AND (
                  list.owner_id = p_user_id
                  OR list.department_id = viewer.department_id
                  OR p_user_id = ANY(COALESCE(list.can_add_users, '{}'::UUID[]))
              )
        );
$$;

CREATE OR REPLACE FUNCTION public.can_view_task_list(p_list_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT public.can_assign_tasks_company_wide(p_user_id)
        OR EXISTS (
            SELECT 1
            FROM public.task_lists list
            JOIN public.profiles viewer ON viewer.id = p_user_id
            WHERE list.id = p_list_id
              AND (
                  list.owner_id = p_user_id
                  OR list.department_id = viewer.department_id
                  OR p_user_id = ANY(COALESCE(list.shared_with, '{}'::UUID[]))
              )
        );
$$;

REVOKE ALL ON FUNCTION public.can_add_task_to_list(UUID, UUID), public.can_view_task_list(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_add_task_to_list(UUID, UUID), public.can_view_task_list(UUID, UUID) TO authenticated;

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_lists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS executive_company_tasks_select ON public.tasks;
CREATE POLICY executive_company_tasks_select ON public.tasks
FOR SELECT TO authenticated
USING (public.can_assign_tasks_company_wide(auth.uid()));

DROP POLICY IF EXISTS executive_company_tasks_insert ON public.tasks;
CREATE POLICY executive_company_tasks_insert ON public.tasks
FOR INSERT TO authenticated
WITH CHECK (created_by = auth.uid() AND public.can_assign_tasks_company_wide(auth.uid()));

DROP POLICY IF EXISTS executive_company_tasks_update ON public.tasks;
CREATE POLICY executive_company_tasks_update ON public.tasks
FOR UPDATE TO authenticated
USING (public.can_assign_tasks_company_wide(auth.uid()))
WITH CHECK (public.can_assign_tasks_company_wide(auth.uid()));

DROP POLICY IF EXISTS executive_company_task_lists_select ON public.task_lists;
CREATE POLICY executive_company_task_lists_select ON public.task_lists
FOR SELECT TO authenticated
USING (public.can_assign_tasks_company_wide(auth.uid()));

NOTIFY pgrst, 'reload schema';

COMMIT;
