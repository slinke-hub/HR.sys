-- Enforce the sidebar page visibility model for employee-owned operational data.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

CREATE OR REPLACE FUNCTION public.is_system_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id=p_user_id
      AND upper(COALESCE(profile.role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_department_manager_for(p_viewer_id UUID,p_employee_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles viewer
    JOIN public.profiles employee ON employee.id=p_employee_id
    WHERE viewer.id=p_viewer_id
      AND viewer.department_id IS NOT NULL
      AND viewer.department_id=employee.department_id
      AND upper(COALESCE(viewer.role,'')) IN ('MANAGER','SUPERVISOR')
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_employee_request(p_source_table TEXT,p_source_id UUID,p_employee_id UUID,p_viewer_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT p_viewer_id=p_employee_id
    OR public.is_system_admin(p_viewer_id)
    OR public.is_department_manager_for(p_viewer_id,p_employee_id)
    OR public.is_request_workflow_approver(p_source_table,p_source_id,p_viewer_id);
$$;

-- Email is exposed only to the employee, their department management, or Admin.
CREATE OR REPLACE FUNCTION public.get_request_filter_directory()
RETURNS TABLE(employee_id UUID,full_name TEXT,email TEXT,department_id UUID)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth,pg_temp AS $$
  SELECT profile.id,COALESCE(profile.full_name,'Unknown User'),COALESCE(account.email::TEXT,''),profile.department_id
  FROM public.profiles profile
  LEFT JOIN auth.users account ON account.id=profile.id
  WHERE profile.is_active=TRUE
    AND (
      profile.id=auth.uid()
      OR public.is_system_admin(auth.uid())
      OR public.is_department_manager_for(auth.uid(),profile.id)
    )
  ORDER BY profile.full_name;
$$;

-- Replace request-table policies so older broad Manager policies cannot leak
-- records from other departments. Workflow approvers retain explicit access.
DO $$ DECLARE item RECORD; BEGIN
  FOR item IN
    SELECT schemaname,tablename,policyname FROM pg_policies
    WHERE schemaname='public' AND tablename IN ('requests','leave_requests','document_requests','expenses')
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',item.policyname,item.tablename); END LOOP;
END $$;

ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY requests_scoped_select ON public.requests FOR SELECT TO authenticated
  USING(public.can_view_employee_request('requests',id,employee_id,auth.uid()));
CREATE POLICY requests_scoped_insert ON public.requests FOR INSERT TO authenticated WITH CHECK(employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(),employee_id));
CREATE POLICY requests_admin_update ON public.requests FOR UPDATE TO authenticated USING(public.is_system_admin(auth.uid())) WITH CHECK(public.is_system_admin(auth.uid()));
CREATE POLICY requests_admin_delete ON public.requests FOR DELETE TO authenticated USING(public.is_system_admin(auth.uid()));

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY leave_requests_scoped_select ON public.leave_requests FOR SELECT TO authenticated
  USING(public.can_view_employee_request('leave_requests',id,employee_id,auth.uid()));
CREATE POLICY leave_requests_scoped_insert ON public.leave_requests FOR INSERT TO authenticated WITH CHECK(employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(),employee_id));
CREATE POLICY leave_requests_admin_update ON public.leave_requests FOR UPDATE TO authenticated USING(public.is_system_admin(auth.uid())) WITH CHECK(public.is_system_admin(auth.uid()));
CREATE POLICY leave_requests_admin_delete ON public.leave_requests FOR DELETE TO authenticated USING(public.is_system_admin(auth.uid()));

ALTER TABLE public.document_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY document_requests_scoped_select ON public.document_requests FOR SELECT TO authenticated
  USING(public.can_view_employee_request('document_requests',id,employee_id,auth.uid()));
CREATE POLICY document_requests_scoped_insert ON public.document_requests FOR INSERT TO authenticated WITH CHECK(employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(),employee_id));
CREATE POLICY document_requests_admin_update ON public.document_requests FOR UPDATE TO authenticated USING(public.is_system_admin(auth.uid())) WITH CHECK(public.is_system_admin(auth.uid()));
CREATE POLICY document_requests_admin_delete ON public.document_requests FOR DELETE TO authenticated USING(public.is_system_admin(auth.uid()));

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY expenses_scoped_select ON public.expenses FOR SELECT TO authenticated
  USING(public.can_view_employee_request('expenses',id,employee_id,auth.uid()));
CREATE POLICY expenses_scoped_insert ON public.expenses FOR INSERT TO authenticated WITH CHECK(employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(),employee_id));
CREATE POLICY expenses_own_update ON public.expenses FOR UPDATE TO authenticated USING(employee_id=auth.uid() OR public.is_system_admin(auth.uid())) WITH CHECK(employee_id=auth.uid() OR public.is_system_admin(auth.uid()));
CREATE POLICY expenses_own_delete ON public.expenses FOR DELETE TO authenticated USING(employee_id=auth.uid() OR public.is_system_admin(auth.uid()));

-- Employees own their documents. Department management sees only its own
-- department, and Admin retains company-wide access.
DO $$ DECLARE item RECORD; BEGIN
  FOR item IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='employee_documents'
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.employee_documents',item.policyname); END LOOP;
END $$;
ALTER TABLE public.employee_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY employee_documents_scoped_select ON public.employee_documents FOR SELECT TO authenticated
  USING(employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(),employee_id));
CREATE POLICY employee_documents_own_insert ON public.employee_documents FOR INSERT TO authenticated WITH CHECK(employee_id=auth.uid());
CREATE POLICY employee_documents_scoped_update ON public.employee_documents FOR UPDATE TO authenticated
  USING(employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(),employee_id))
  WITH CHECK(employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(),employee_id));
CREATE POLICY employee_documents_scoped_delete ON public.employee_documents FOR DELETE TO authenticated
  USING(employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(),employee_id));

-- Attendance is private to the employee. Admin and HR Manager retain the
-- previously approved company-wide reporting access.
DO $$ DECLARE item RECORD; BEGIN
  FOR item IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='attendance'
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.attendance',item.policyname); END LOOP;
END $$;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
CREATE POLICY attendance_scoped_select ON public.attendance FOR SELECT TO authenticated USING(
  employee_id=auth.uid() OR public.is_system_admin(auth.uid()) OR EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=auth.uid() AND upper(BTRIM(COALESCE(profile.job_title,'')))='HR MANAGER'
  )
);
CREATE POLICY attendance_own_insert ON public.attendance FOR INSERT TO authenticated WITH CHECK(employee_id=auth.uid());
CREATE POLICY attendance_own_update ON public.attendance FOR UPDATE TO authenticated USING(employee_id=auth.uid()) WITH CHECK(employee_id=auth.uid());

-- Employees see and interact only with assigned or watched tasks. Managers,
-- supervisors and Admin retain their established task-management access.
CREATE OR REPLACE FUNCTION public.can_view_task(p_task_id UUID,p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.tasks task
    LEFT JOIN public.projects project ON project.id=task.project_id
    LEFT JOIN public.profiles viewer ON viewer.id=p_user_id
    WHERE task.id=p_task_id AND p_user_id IS NOT NULL AND (
      (upper(COALESCE(viewer.role,''))='EMPLOYEE' AND (task.assignee_id=p_user_id OR p_user_id=ANY(COALESCE(task.watchers,'{}'))))
      OR (upper(COALESCE(viewer.role,''))<>'EMPLOYEE' AND (
        public.is_task_admin(p_user_id)
        OR p_user_id IN (task.created_by,task.assignee_id,task.supervisor_id)
        OR p_user_id=ANY(COALESCE(task.watchers,'{}'))
        OR p_user_id=ANY(COALESCE(task.visible_to,'{}'))
        OR p_user_id=ANY(COALESCE(project.assigned_people,'{}'))
        OR EXISTS(SELECT 1 FROM public.departments department WHERE department.name=task.department AND department.head_id=p_user_id)
        OR task.visibility='public'
        OR (task.visibility='team' AND EXISTS(
          SELECT 1 FROM public.profiles owner WHERE owner.id IN(task.created_by,task.assignee_id)
            AND (viewer.department_id=owner.department_id OR owner.manager_id=p_user_id OR viewer.manager_id=owner.manager_id)
        ))
      ))
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_task(p_task_id UUID,p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.tasks task JOIN public.profiles viewer ON viewer.id=p_user_id
    WHERE task.id=p_task_id AND (
      (upper(COALESCE(viewer.role,''))='EMPLOYEE' AND (task.assignee_id=p_user_id OR p_user_id=ANY(COALESCE(task.watchers,'{}'))))
      OR (upper(COALESCE(viewer.role,''))<>'EMPLOYEE' AND (
        public.is_task_admin(p_user_id) OR p_user_id IN(task.created_by,task.assignee_id,task.supervisor_id)
        OR EXISTS(SELECT 1 FROM public.departments department WHERE department.name=task.department AND department.head_id=p_user_id)
      ))
    )
  );
$$;

DO $$ DECLARE item RECORD; BEGIN
  FOR item IN SELECT tablename,policyname FROM pg_policies WHERE schemaname='public' AND tablename IN ('tasks','task_comments')
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',item.policyname,item.tablename); END LOOP;
END $$;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY tasks_select_authorized ON public.tasks FOR SELECT TO authenticated USING(public.can_view_task(id,auth.uid()));
CREATE POLICY tasks_insert_own ON public.tasks FOR INSERT TO authenticated WITH CHECK(created_by=auth.uid() AND (parent_task_id IS NULL OR public.can_view_task(parent_task_id,auth.uid())));
CREATE POLICY tasks_update_authorized ON public.tasks FOR UPDATE TO authenticated USING(public.can_manage_task(id,auth.uid())) WITH CHECK(public.can_manage_task(id,auth.uid()));
CREATE POLICY tasks_delete_creator_or_admin ON public.tasks FOR DELETE TO authenticated USING(created_by=auth.uid() OR public.is_task_admin(auth.uid()));
ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY task_comments_select_authorized ON public.task_comments FOR SELECT TO authenticated USING(public.can_view_task(task_id,auth.uid()));
CREATE POLICY task_comments_insert_authorized ON public.task_comments FOR INSERT TO authenticated WITH CHECK(user_id=auth.uid() AND public.can_view_task(task_id,auth.uid()));
CREATE POLICY task_comments_update_own ON public.task_comments FOR UPDATE TO authenticated USING(user_id=auth.uid() OR public.is_task_admin(auth.uid())) WITH CHECK(user_id=auth.uid() OR public.is_task_admin(auth.uid()));
CREATE POLICY task_comments_delete_own ON public.task_comments FOR DELETE TO authenticated USING(user_id=auth.uid() OR public.is_task_admin(auth.uid()));

REVOKE ALL ON FUNCTION public.get_request_filter_directory() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_request_filter_directory() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_system_admin(UUID),public.is_department_manager_for(UUID,UUID),public.can_view_employee_request(TEXT,UUID,UUID,UUID) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
