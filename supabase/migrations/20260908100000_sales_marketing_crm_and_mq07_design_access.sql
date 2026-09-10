-- Extend CRM access to Sales, Marketing, CEO, and GM users, and grant MQ-07
-- scoped Design-list access with same-department assignment enforcement.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_access_crm(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        LEFT JOIN public.departments department ON department.id = profile.department_id
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM false
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'CEO', 'GM', 'GENERAL MANAGER'
              )
              OR UPPER(COALESCE(profile.job_title, '')) ~ '(^|[^A-Z])(CEO|GM|GENERAL MANAGER|SALES|MARKETING)([^A-Z]|$)'
              OR COALESCE(profile.job_title, '') ~ '(المبيعات|التسويق)'
              OR COALESCE(department.name, '') ~* '(sales|marketing|المبيعات|التسويق)'
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_access_crm(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_crm(uuid) TO authenticated;

ALTER TABLE public.crm_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_approval_steps ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_clients TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_deals TO authenticated;
GRANT SELECT, INSERT ON public.crm_deal_activity TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.crm_deal_attachments TO authenticated;
GRANT SELECT ON public.crm_deal_approval_steps TO authenticated;

DROP POLICY IF EXISTS crm_authorized_clients_all ON public.crm_clients;
CREATE POLICY crm_authorized_clients_all ON public.crm_clients
FOR ALL TO authenticated
USING (public.can_access_crm(auth.uid()))
WITH CHECK (public.can_access_crm(auth.uid()));

DROP POLICY IF EXISTS crm_authorized_deals_all ON public.crm_deals;
CREATE POLICY crm_authorized_deals_all ON public.crm_deals
FOR ALL TO authenticated
USING (public.can_access_crm(auth.uid()))
WITH CHECK (public.can_access_crm(auth.uid()));

DROP POLICY IF EXISTS crm_authorized_activity_select ON public.crm_deal_activity;
CREATE POLICY crm_authorized_activity_select ON public.crm_deal_activity
FOR SELECT TO authenticated
USING (public.can_access_crm(auth.uid()));

DROP POLICY IF EXISTS crm_authorized_activity_insert ON public.crm_deal_activity;
CREATE POLICY crm_authorized_activity_insert ON public.crm_deal_activity
FOR INSERT TO authenticated
WITH CHECK (public.can_access_crm(auth.uid()));

DROP POLICY IF EXISTS crm_authorized_attachments_select ON public.crm_deal_attachments;
CREATE POLICY crm_authorized_attachments_select ON public.crm_deal_attachments
FOR SELECT TO authenticated
USING (public.can_access_crm(auth.uid()));

DROP POLICY IF EXISTS crm_authorized_attachments_insert ON public.crm_deal_attachments;
CREATE POLICY crm_authorized_attachments_insert ON public.crm_deal_attachments
FOR INSERT TO authenticated
WITH CHECK (public.can_access_crm(auth.uid()));

DROP POLICY IF EXISTS crm_authorized_attachments_delete ON public.crm_deal_attachments;
CREATE POLICY crm_authorized_attachments_delete ON public.crm_deal_attachments
FOR DELETE TO authenticated
USING (public.can_access_crm(auth.uid()));

DROP POLICY IF EXISTS crm_authorized_approval_steps_select ON public.crm_deal_approval_steps;
CREATE POLICY crm_authorized_approval_steps_select ON public.crm_deal_approval_steps
FOR SELECT TO authenticated
USING (public.can_access_crm(auth.uid()));

CREATE OR REPLACE FUNCTION public.is_mq07_design_list(
    p_list_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        JOIN public.task_lists list
          ON list.id = p_list_id
         AND list.department_id = profile.department_id
        WHERE profile.id = p_user_id
          AND profile.emp_index = 7
          AND profile.is_active IS DISTINCT FROM false
          AND COALESCE(list.name, '') ~* '(design|تصميم)'
    );
$$;

REVOKE ALL ON FUNCTION public.is_mq07_design_list(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_mq07_design_list(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS mq07_design_list_select ON public.task_lists;
CREATE POLICY mq07_design_list_select ON public.task_lists
FOR SELECT TO authenticated
USING (public.is_mq07_design_list(id, auth.uid()));

DROP POLICY IF EXISTS mq07_design_tasks_select ON public.tasks;
CREATE POLICY mq07_design_tasks_select ON public.tasks
FOR SELECT TO authenticated
USING (public.is_mq07_design_list(task_list_id, auth.uid()));

DROP POLICY IF EXISTS mq07_design_tasks_insert ON public.tasks;
CREATE POLICY mq07_design_tasks_insert ON public.tasks
FOR INSERT TO authenticated
WITH CHECK (
    created_by = auth.uid()
    AND public.is_mq07_design_list(task_list_id, auth.uid())
);

DROP POLICY IF EXISTS mq07_design_tasks_update_own ON public.tasks;
CREATE POLICY mq07_design_tasks_update_own ON public.tasks
FOR UPDATE TO authenticated
USING (
    created_by = auth.uid()
    AND public.is_mq07_design_list(task_list_id, auth.uid())
)
WITH CHECK (
    created_by = auth.uid()
    AND public.is_mq07_design_list(task_list_id, auth.uid())
);

CREATE OR REPLACE FUNCTION public.enforce_mq07_design_assignment_department()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    caller_department uuid;
    invalid_assignee uuid;
BEGIN
    IF NOT public.is_mq07_design_list(NEW.task_list_id, auth.uid()) THEN
        RETURN NEW;
    END IF;

    IF NEW.created_by IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'MQ-07 may only create or edit their own Design tasks'
            USING ERRCODE = '42501';
    END IF;

    SELECT department_id INTO caller_department
    FROM public.profiles
    WHERE id = auth.uid() AND emp_index = 7;

    SELECT candidate.id INTO invalid_assignee
    FROM unnest(
        array_remove(
            COALESCE(NEW.assignee_ids, '{}'::uuid[]) || ARRAY[NEW.assignee_id]::uuid[],
            NULL
        )
    ) candidate(id)
    LEFT JOIN public.profiles assignee ON assignee.id = candidate.id
    WHERE assignee.id IS NULL
       OR assignee.is_active IS FALSE
       OR assignee.department_id IS DISTINCT FROM caller_department
    LIMIT 1;

    IF invalid_assignee IS NOT NULL THEN
        RAISE EXCEPTION 'Design tasks may only be assigned to active employees in MQ-07''s department'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_mq07_design_assignment_department_trigger ON public.tasks;
CREATE TRIGGER enforce_mq07_design_assignment_department_trigger
BEFORE INSERT OR UPDATE OF assignee_id, assignee_ids, task_list_id, created_by
ON public.tasks
FOR EACH ROW
EXECUTE FUNCTION public.enforce_mq07_design_assignment_department();

NOTIFY pgrst, 'reload schema';
COMMIT;
