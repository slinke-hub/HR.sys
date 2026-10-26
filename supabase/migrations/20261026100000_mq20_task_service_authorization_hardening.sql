-- Keep MQ-20 task access view-only across the SECURITY DEFINER Task Manager API.
-- The task row guard permits only the CRM-owned Contact task insertion already
-- authorized by the deal transition RPC and recorded in crm_generated_tasks.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_is_own_generated_contact_task(p_task_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_task_id IS NOT NULL
    AND p_user_id IS NOT NULL
    AND p_user_id = auth.uid()
    AND public.is_mq20_profile(p_user_id)
    AND EXISTS (
      SELECT 1
      FROM public.crm_generated_tasks generated
      JOIN public.tasks task ON task.id = generated.task_id
      WHERE generated.task_id = p_task_id
        AND generated.kind = 'CONTACT_DISCUSSION'
        AND generated.deal_id = task.crm_deal_id
        AND task.crm_workflow_kind = 'CONTACT_DISCUSSION'
        AND task.created_by = p_user_id
        AND task.assignee_id = p_user_id
        AND p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
    );
$$;
REVOKE ALL ON FUNCTION public.crm_is_own_generated_contact_task(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_is_own_generated_contact_task(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_access_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tasks task
    WHERE task.id = p_task_id
      AND p_user_id IS NOT NULL
      AND (auth.uid() IS NULL OR p_user_id = auth.uid())
      AND (
        auth.uid() IS NULL
        OR NOT public.is_mq20_profile(auth.uid())
        OR public.is_ines_modani_task(task.id)
        OR public.crm_is_own_generated_contact_task(task.id, auth.uid())
      )
      AND (
        task.created_by = p_user_id
        OR task.assignee_id = p_user_id
        OR task.supervisor_id = p_user_id
        OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
        OR p_user_id = ANY(COALESCE(task.visible_to, '{}'::uuid[]))
        OR public.can_assign_tasks_company_wide(p_user_id)
        OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
        OR public.can_view_task_via_employee_grant(p_task_id, p_user_id)
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list(task.task_list_id, p_user_id))
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list_via_employee_grant(task.task_list_id, p_user_id))
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND (auth.uid() IS NULL OR p_user_id = auth.uid())
    AND (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
    AND EXISTS (
      SELECT 1
      FROM public.tasks task
      LEFT JOIN public.task_lists list ON list.id = task.task_list_id
      WHERE task.id = p_task_id
        AND (
          task.created_by = p_user_id
          OR task.supervisor_id = p_user_id
          OR public.can_assign_tasks_company_wide(p_user_id)
          OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
          OR p_user_id = ANY(COALESCE(list.can_delete_users, '{}'::uuid[]))
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_execute_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND (auth.uid() IS NULL OR p_user_id = auth.uid())
    AND (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
    AND EXISTS (
      SELECT 1
      FROM public.tasks task
      JOIN public.profiles profile ON profile.id = p_user_id
      WHERE task.id = p_task_id
        AND profile.is_active IS DISTINCT FROM false
        AND (
          profile.id IN (task.created_by, task.assignee_id, task.supervisor_id)
          OR profile.id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
          OR UPPER(COALESCE(profile.role, '')) IN ('ADMIN', 'MANAGER', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'CEO', 'GM', 'GENERAL MANAGER')
          OR UPPER(COALESCE(profile.job_title, '')) IN ('CEO', 'GM', 'GENERAL MANAGER')
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_task_attachments(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND (auth.uid() IS NULL OR p_user_id = auth.uid())
    AND (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
    AND EXISTS (
      SELECT 1
      FROM public.tasks task
      LEFT JOIN public.projects project ON project.id = task.project_id
      WHERE task.id = p_task_id
        AND (
          task.created_by = p_user_id
          OR task.assignee_id = p_user_id
          OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
          OR task.supervisor_id = p_user_id
          OR project.created_by = p_user_id
          OR project.project_manager_id = p_user_id
          OR public.is_project_portfolio_admin(p_user_id)
        )
    );
$$;

-- Preserve the ordinary project-assignee file rule, while MQ-20 must pass the
-- same task-visibility check as all other task detail readers.
CREATE OR REPLACE FUNCTION public.can_read_task_attachment_file(p_object_name text, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_user_id IS NULL OR (auth.uid() IS NOT NULL AND p_user_id <> auth.uid()) THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.task_attachments attachment
    JOIN public.tasks task ON task.id = attachment.task_id
    LEFT JOIN public.projects project ON project.id = task.project_id
    WHERE attachment.file_url = 'storage://task-attachments/' || p_object_name
      AND (
        public.can_access_task(task.id, p_user_id)
        OR (
          (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
          AND project.id IS NOT NULL
          AND p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::uuid[]))
        )
      )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_mq20_task_service_boundaries()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  caller_id uuid := auth.uid();
BEGIN
  IF caller_id IS NULL OR NOT public.is_mq20_profile(caller_id) THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'tasks' THEN
    IF TG_OP = 'INSERT'
       AND NEW.created_by = caller_id
       AND NEW.assignee_id = caller_id
       AND caller_id = ANY(COALESCE(NEW.assignee_ids, '{}'::uuid[]))
       AND NEW.crm_workflow_kind = 'CONTACT_DISCUSSION'
       AND EXISTS (
         SELECT 1 FROM public.crm_generated_tasks generated
         WHERE generated.task_id = NEW.id
           AND generated.deal_id = NEW.crm_deal_id
           AND generated.kind = 'CONTACT_DISCUSSION'
       ) THEN
      RETURN NEW;
    END IF;
  END IF;

  RAISE EXCEPTION 'MQ-20 task access is view-only' USING ERRCODE = '42501';
END;
$$;
REVOKE ALL ON FUNCTION public.enforce_mq20_task_service_boundaries() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS mq20_task_service_view_only ON public.tasks;
CREATE TRIGGER mq20_task_service_view_only
BEFORE INSERT OR UPDATE OR DELETE ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.enforce_mq20_task_service_boundaries();

-- SECURITY DEFINER RPCs can bypass RLS, so enforce the same view-only rule at
-- the rows they would mutate. The trigger is conditional and leaves every
-- non-MQ-20 caller's existing service authorization unchanged.
DO $$
DECLARE
  target_table text;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'task_comments', 'task_attachments', 'task_dependencies',
    'task_waiting_history', 'task_blocker_history', 'task_lists'
  ] LOOP
    IF to_regclass(format('public.%I', target_table)) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'mq20_view_only_' || target_table, target_table);
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_mq20_task_service_boundaries()',
        'mq20_view_only_' || target_table, target_table
      );
    END IF;
  END LOOP;
END;
$$;

-- The task exception also permits read-only inspection of that task's own
-- comments and registered attachments, without changing their write policies.
DROP POLICY IF EXISTS mq20_only_ines_task_comments_select ON public.task_comments;
CREATE POLICY mq20_only_ines_task_comments_select ON public.task_comments AS RESTRICTIVE
  FOR SELECT TO authenticated
  USING (
    NOT public.is_mq20_profile(auth.uid())
    OR public.is_ines_modani_task(task_id)
    OR public.crm_is_own_generated_contact_task(task_id, auth.uid())
  );

DROP POLICY IF EXISTS mq20_only_ines_task_attachments_select ON public.task_attachments;
CREATE POLICY mq20_only_ines_task_attachments_select ON public.task_attachments AS RESTRICTIVE
  FOR SELECT TO authenticated
  USING (
    NOT public.is_mq20_profile(auth.uid())
    OR public.is_ines_modani_task(task_id)
    OR public.crm_is_own_generated_contact_task(task_id, auth.uid())
  );

NOTIFY pgrst, 'reload schema';
COMMIT;
