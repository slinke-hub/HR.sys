-- CRM Presentation options, repeatable approvals, Design-task review, and Won order details.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.crm_deals
    ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS approval_type text,
    ADD COLUMN IF NOT EXISTS design_task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL;

UPDATE public.crm_deals SET created_by = assigned_to WHERE created_by IS NULL;

ALTER TABLE public.crm_deals DROP CONSTRAINT IF EXISTS crm_deals_approval_type_check;
ALTER TABLE public.crm_deals ADD CONSTRAINT crm_deals_approval_type_check
    CHECK (approval_type IS NULL OR approval_type IN ('QUOTE', 'QUOTE_PROPOSAL'));
ALTER TABLE public.crm_deals DROP CONSTRAINT IF EXISTS crm_deals_workflow_status_check;
ALTER TABLE public.crm_deals ADD CONSTRAINT crm_deals_workflow_status_check
    CHECK (workflow_status IN (
        'NOT_STARTED', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED',
        'DESIGN_IN_PROGRESS', 'DESIGN_PENDING_APPROVAL', 'DESIGN_REJECTED'
    ));

ALTER TABLE public.crm_deal_approval_steps DROP CONSTRAINT IF EXISTS crm_deal_approval_steps_step_order_check;
ALTER TABLE public.crm_deal_approval_steps DROP CONSTRAINT IF EXISTS crm_deal_approval_steps_stage_key_check;
ALTER TABLE public.crm_deal_approval_steps ADD CONSTRAINT crm_deal_approval_steps_step_order_check
    CHECK (step_order BETWEEN 1 AND 5);
ALTER TABLE public.crm_deal_approval_steps ADD CONSTRAINT crm_deal_approval_steps_stage_key_check
    CHECK (stage_key IN ('CEO', 'GENERAL_MANAGER', 'MQ_04', 'MQ_05', 'MARKETING_MANAGER', 'OPERATIONS_MANAGER'));

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS crm_deal_id uuid REFERENCES public.crm_deals(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS crm_workflow_kind text;

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_crm_workflow_kind_check;
ALTER TABLE public.tasks ADD CONSTRAINT tasks_crm_workflow_kind_check
    CHECK (crm_workflow_kind IS NULL OR crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN');

CREATE INDEX IF NOT EXISTS tasks_crm_deal_id_idx ON public.tasks(crm_deal_id);

CREATE TABLE IF NOT EXISTS public.crm_design_task_approval_steps (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    step_order integer NOT NULL CHECK (step_order BETWEEN 1 AND 5),
    stage_key text NOT NULL CHECK (stage_key IN ('CEO', 'GENERAL_MANAGER', 'MQ_04', 'MQ_05', 'MARKETING_MANAGER')),
    approver_id uuid NOT NULL REFERENCES public.profiles(id),
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    decision_note text,
    decided_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (task_id, stage_key)
);

CREATE INDEX IF NOT EXISTS crm_design_task_approval_pending_idx
    ON public.crm_design_task_approval_steps(approver_id, status, created_at DESC);

ALTER TABLE public.crm_design_task_approval_steps ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.crm_design_task_approval_steps TO authenticated;
DROP POLICY IF EXISTS crm_design_task_approval_select ON public.crm_design_task_approval_steps;
CREATE POLICY crm_design_task_approval_select ON public.crm_design_task_approval_steps
FOR SELECT TO authenticated USING (
    approver_id = auth.uid()
    OR public.can_access_crm(auth.uid())
    OR EXISTS (SELECT 1 FROM public.tasks task WHERE task.id = task_id AND auth.uid() IN (task.assignee_id, task.created_by))
);

ALTER TABLE public.projects
    ADD COLUMN IF NOT EXISTS order_employee_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS event_start_time time,
    ADD COLUMN IF NOT EXISTS installation_time time,
    ADD COLUMN IF NOT EXISTS uninstallation_time time,
    ADD COLUMN IF NOT EXISTS client_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS event_location_text text,
    ADD COLUMN IF NOT EXISTS installation_type text,
    ADD COLUMN IF NOT EXISTS equipment jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_installation_type_check;
ALTER TABLE public.projects ADD CONSTRAINT projects_installation_type_check
    CHECK (installation_type IS NULL OR installation_type IN ('INDOOR', 'OUTDOOR', 'INDOOR_OUTDOOR'));

CREATE OR REPLACE FUNCTION public.is_crm_approval_admin(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g')))
              IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
    );
$$;

CREATE OR REPLACE FUNCTION public.start_crm_presentation_approval(p_deal_id uuid, p_request_type text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_ceo uuid;
    v_gm uuid;
    v_mq04 uuid;
    v_mq05 uuid;
    v_marketing uuid;
BEGIN
    p_request_type := UPPER(BTRIM(COALESCE(p_request_type, '')));
    IF p_request_type NOT IN ('QUOTE', 'QUOTE_PROPOSAL') THEN
        RAISE EXCEPTION 'Choose Quote or Quote and proposal';
    END IF;

    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deal not found'; END IF;
    IF auth.uid() IS DISTINCT FROM COALESCE(v_deal.created_by, v_deal.assigned_to)
       AND auth.uid() IS DISTINCT FROM v_deal.assigned_to
       AND NOT public.is_crm_approval_admin(auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND UPPER(COALESCE(p.role, '')) = 'MANAGER') THEN
        RAISE EXCEPTION 'Only the deal creator, assignee, or management can send this request';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id = p_deal_id AND category = 'QUOTATION') THEN
        RAISE EXCEPTION 'Upload a quote document first';
    END IF;
    IF p_request_type = 'QUOTE_PROPOSAL'
       AND NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id = p_deal_id AND category = 'PROPOSAL') THEN
        RAISE EXCEPTION 'Upload at least one proposal image first';
    END IF;

    SELECT id INTO v_ceo FROM public.profiles
    WHERE is_active IS DISTINCT FROM false
      AND (UPPER(BTRIM(COALESCE(role, ''))) = 'CEO' OR UPPER(COALESCE(job_title, '')) ~ '(^|[^A-Z])(CEO|CHIEF EXECUTIVE)([^A-Z]|$)')
    ORDER BY emp_index NULLS LAST LIMIT 1;
    SELECT id INTO v_gm FROM public.profiles
    WHERE is_active IS DISTINCT FROM false
      AND (UPPER(BTRIM(COALESCE(role, ''))) IN ('GM', 'GENERAL MANAGER') OR UPPER(COALESCE(job_title, '')) ~ '(^|[^A-Z])(GM|GENERAL MANAGER)([^A-Z]|$)')
    ORDER BY emp_index NULLS LAST LIMIT 1;
    SELECT id INTO v_marketing FROM public.profiles
    WHERE is_active IS DISTINCT FROM false
      AND (UPPER(COALESCE(job_title, '')) ~ 'MARKETING.*MANAGER|MANAGER.*MARKETING' OR COALESCE(job_title, '') ~ 'مدير.*التسويق')
    ORDER BY emp_index NULLS LAST LIMIT 1;
    SELECT id INTO v_mq04 FROM public.profiles WHERE emp_index = 4 AND is_active IS DISTINCT FROM false LIMIT 1;
    SELECT id INTO v_mq05 FROM public.profiles WHERE emp_index = 5 AND is_active IS DISTINCT FROM false LIMIT 1;

    IF v_ceo IS NULL OR v_gm IS NULL OR v_marketing IS NULL THEN
        RAISE EXCEPTION 'CEO, GM, and Marketing Manager accounts must be configured';
    END IF;
    IF p_request_type = 'QUOTE_PROPOSAL' AND (v_mq04 IS NULL OR v_mq05 IS NULL) THEN
        RAISE EXCEPTION 'Employee MQ-04 and MQ-05 accounts must be configured';
    END IF;

    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;
    INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
    VALUES (p_deal_id, 1, 'CEO', v_ceo), (p_deal_id, 2, 'GENERAL_MANAGER', v_gm);
    IF p_request_type = 'QUOTE_PROPOSAL' THEN
        INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
        VALUES (p_deal_id, 3, 'MQ_04', v_mq04), (p_deal_id, 4, 'MQ_05', v_mq05), (p_deal_id, 5, 'MARKETING_MANAGER', v_marketing);
    ELSE
        INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
        VALUES (p_deal_id, 3, 'MARKETING_MANAGER', v_marketing);
    END IF;

    UPDATE public.crm_deals
       SET stage = 'PITCH', approval_type = p_request_type, workflow_status = 'PENDING_APPROVAL', proposal_sent_at = now()
     WHERE id = p_deal_id;

    INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
    SELECT step.approver_id,
           CASE WHEN p_request_type = 'QUOTE' THEN 'Quote approval requested: ' ELSE 'Quote and proposal approval requested: ' END || v_deal.title,
           'crm_approval_requested', auth.uid(), '/?view=approvals',
           jsonb_build_object('deal_id', p_deal_id, 'step_id', step.id, 'stage_key', step.stage_key, 'request_type', p_request_type)
    FROM public.crm_deal_approval_steps step WHERE step.deal_id = p_deal_id;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (p_deal_id, 'PRESENTATION_APPROVAL_STARTED', v_deal.stage, 'PITCH', p_request_type, auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_private_task_list_ownership()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF NEW.task_list_id IS NULL THEN RETURN NEW; END IF;
    IF current_setting('app.crm_design_task_creation', true) = 'on' AND NEW.crm_deal_id IS NOT NULL THEN
        NEW.visibility := 'private';
        RETURN NEW;
    END IF;
    IF NOT public.can_add_task_to_list(NEW.task_list_id, auth.uid()) THEN
        RAISE EXCEPTION 'You cannot add tasks to this task list' USING ERRCODE = '42501';
    END IF;
    NEW.visibility := 'private';
    NEW.visible_to := '{}';
    NEW.supervisor_id := NULL;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_task_completion_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    -- CRM Design tasks have their own five-person completion approval cycle.
    -- Leave the requested completion intact so the dedicated trigger can
    -- convert it to Pending Approval and create those review steps.
    IF NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'
       AND current_setting('app.crm_design_task_finalize', true) IS DISTINCT FROM 'on' THEN
        RETURN NEW;
    END IF;
    IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
        IF current_setting('app.crm_design_task_finalize', true) = 'on' AND NEW.crm_deal_id IS NOT NULL THEN
            NEW.completion_approved_by := auth.uid();
            NEW.completion_approved_at := now();
        ELSIF public.is_task_department_manager(NEW.department, auth.uid()) THEN
            NEW.completion_approved_by := auth.uid();
            NEW.completion_approved_at := now();
        ELSE
            NEW.status := 'Pending Approval';
            NEW.completion_requested_by := auth.uid();
            NEW.completion_requested_at := now();
            NEW.completion_approved_by := NULL;
            NEW.completion_approved_at := NULL;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_marketing_design_review()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE is_designing boolean;
BEGIN
    -- CRM proposal tasks use the dedicated approval cycle below.
    IF NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN' THEN RETURN NEW; END IF;
    is_designing := NEW.department = 'Marketing' AND NEW.sub_type = 'Designing Task';
    IF NOT is_designing THEN RETURN NEW; END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.delivery_status IS NOT NULL AND NOT public.is_marketing_department_manager(auth.uid()) THEN
            RAISE EXCEPTION 'Only the Marketing department manager can set Delivery Status' USING ERRCODE = '42501';
        END IF;
        NEW.status := CASE WHEN NEW.delivery_status = 'Approved' THEN 'completed' ELSE 'review' END;
        RETURN NEW;
    END IF;
    IF NEW.delivery_status IS DISTINCT FROM OLD.delivery_status
       AND NOT public.is_marketing_department_manager(auth.uid()) THEN
        RAISE EXCEPTION 'Only the Marketing department manager can change Delivery Status' USING ERRCODE = '42501';
    END IF;
    IF NEW.delivery_status IS DISTINCT FROM OLD.delivery_status THEN
        NEW.status := CASE WHEN NEW.delivery_status = 'Approved' THEN 'completed' ELSE 'review' END;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_crm_design_task_for_deal(p_deal_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_designer uuid;
    v_list_id uuid;
    v_department text;
    v_task_id uuid;
    v_watchers uuid[];
    v_notification_id uuid;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND OR v_deal.approval_type <> 'QUOTE_PROPOSAL' OR v_deal.workflow_status <> 'APPROVED' THEN
        RAISE EXCEPTION 'The quote and proposal approval must be completed first';
    END IF;
    SELECT id INTO v_designer FROM public.profiles WHERE emp_index = 8 AND is_active IS DISTINCT FROM false LIMIT 1;
    IF v_designer IS NULL THEN RAISE EXCEPTION 'Employee MQ-08 must be configured'; END IF;

    SELECT list.id, COALESCE(department.name, 'Design') INTO v_list_id, v_department
    FROM public.task_lists list LEFT JOIN public.departments department ON department.id = list.department_id
    WHERE COALESCE(list.name, '') ~* '(design|تصميم)'
    ORDER BY CASE WHEN COALESCE(list.name, '') ~* '^design$' THEN 0 ELSE 1 END, list.created_at LIMIT 1;
    IF v_list_id IS NULL THEN RAISE EXCEPTION 'The Design task list must be configured'; END IF;

    SELECT array_agg(DISTINCT approver_id) INTO v_watchers
    FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;
    PERFORM set_config('app.crm_design_task_creation', 'on', true);
    INSERT INTO public.tasks(
        title, title_i18n, description, description_i18n, assignee_id, created_by, status, priority, category,
        visibility, task_list_id, department, sub_type, content_type, watchers,
        visible_to, notify_via_email, crm_deal_id, crm_workflow_kind
    ) VALUES (
        'Design approved proposal: ' || v_deal.title,
        jsonb_build_object('en', 'Design approved proposal: ' || v_deal.title, 'ar', 'تصميم العرض المعتمد: ' || v_deal.title),
        COALESCE(v_deal.technical_description, 'Prepare the approved CRM proposal design.'),
        jsonb_build_object(
            'en', COALESCE(v_deal.technical_description, 'Prepare the approved CRM proposal design.'),
            'ar', COALESCE(v_deal.technical_description, 'إعداد تصميم عرض إدارة علاقات العملاء المعتمد.')
        ),
        v_designer, COALESCE(v_deal.created_by, v_deal.assigned_to, auth.uid()), 'todo', 'high', 'CRM',
        'private', v_list_id, v_department, 'Designing Task', 'Proposal', COALESCE(v_watchers, '{}'),
        COALESCE(v_watchers, '{}'), false, p_deal_id, 'QUOTE_PROPOSAL_DESIGN'
    ) RETURNING id INTO v_task_id;

    UPDATE public.crm_deals SET design_task_id = v_task_id, workflow_status = 'DESIGN_IN_PROGRESS' WHERE id = p_deal_id;

    SELECT id INTO v_notification_id FROM public.notifications
    WHERE task_id = v_task_id AND user_id = v_designer ORDER BY created_at DESC LIMIT 1;
    IF v_notification_id IS NULL THEN
        INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
        VALUES (v_designer, 'New CRM proposal Design task: ' || v_deal.title, 'crm_design_task_assigned', v_task_id, auth.uid(), '/?view=tasks', jsonb_build_object('deal_id', p_deal_id))
        RETURNING id INTO v_notification_id;
    ELSE
        UPDATE public.notifications
           SET message = 'New CRM proposal Design task: ' || v_deal.title,
               event_type = 'crm_design_task_assigned',
               metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('deal_id', p_deal_id)
         WHERE id = v_notification_id;
    END IF;
    INSERT INTO public.task_email_outbox(notification_id, task_id, recipient_id, recipient_email, subject, message, action_url, always_send)
    SELECT v_notification_id, v_task_id, profile.id, auth_user.email,
           'New CRM proposal Design task: ' || v_deal.title,
           'A new CRM proposal Design task has been assigned to you.', '/?view=tasks', true
    FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
    WHERE profile.id = v_designer AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.task_email_outbox outbox WHERE outbox.task_id = v_task_id AND outbox.recipient_id = v_designer);
    RETURN v_task_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_deal_approval(p_step_id uuid, p_decision text, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_step public.crm_deal_approval_steps%ROWTYPE;
    v_deal public.crm_deals%ROWTYPE;
    v_remaining integer;
    v_owner uuid;
BEGIN
    p_decision := UPPER(BTRIM(COALESCE(p_decision, '')));
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'Invalid approval decision'; END IF;
    IF p_decision = 'REJECTED' AND NULLIF(BTRIM(COALESCE(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'A rejection reason is required'; END IF;
    SELECT * INTO v_step FROM public.crm_deal_approval_steps WHERE id = p_step_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;
    UPDATE public.crm_deal_approval_steps SET status = p_decision, decision_note = NULLIF(BTRIM(p_note), ''), decided_at = now()
    WHERE id = p_step_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval has already been decided'; END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_step.deal_id;
    v_owner := COALESCE(v_deal.created_by, v_deal.assigned_to);
    IF p_decision = 'REJECTED' THEN
        UPDATE public.crm_deals SET workflow_status = 'REJECTED' WHERE id = v_step.deal_id;
        IF v_owner IS NOT NULL THEN
            INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
            VALUES (v_owner, 'CRM request rejected: ' || v_deal.title || '. Reason: ' || BTRIM(p_note), 'crm_approval_rejected', auth.uid(), '/?view=crm', jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note), 'request_type', v_deal.approval_type));
        END IF;
    ELSE
        SELECT count(*) INTO v_remaining FROM public.crm_deal_approval_steps WHERE deal_id = v_deal.id AND status <> 'APPROVED';
        IF v_remaining = 0 THEN
            UPDATE public.crm_deals SET workflow_status = 'APPROVED' WHERE id = v_deal.id;
            IF v_deal.approval_type = 'QUOTE_PROPOSAL' THEN
                PERFORM public.create_crm_design_task_for_deal(v_deal.id);
            ELSE
                UPDATE public.crm_deals SET stage = 'NEGOTIATION' WHERE id = v_deal.id;
            END IF;
            IF v_owner IS NOT NULL THEN
                INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
                VALUES (v_owner, 'CRM approval completed: ' || v_deal.title, 'crm_approval_completed', auth.uid(), '/?view=crm', jsonb_build_object('deal_id', v_deal.id, 'request_type', v_deal.approval_type));
            END IF;
        END IF;
    END IF;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (v_deal.id, 'APPROVAL_DECISION', 'PENDING', p_decision, p_note, auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_crm_design_task_completion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'
       AND NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed'
       AND current_setting('app.crm_design_task_finalize', true) IS DISTINCT FROM 'on' THEN
        DELETE FROM public.crm_design_task_approval_steps WHERE task_id = NEW.id;
        INSERT INTO public.crm_design_task_approval_steps(task_id, deal_id, step_order, stage_key, approver_id)
        SELECT NEW.id, NEW.crm_deal_id, step.step_order, step.stage_key, step.approver_id
        FROM public.crm_deal_approval_steps step WHERE step.deal_id = NEW.crm_deal_id ORDER BY step.step_order;
        NEW.status := 'Pending Approval';
        NEW.completion_requested_by := auth.uid();
        NEW.completion_requested_at := now();
        NEW.completion_approved_by := NULL;
        NEW.completion_approved_at := NULL;
        UPDATE public.crm_deals SET workflow_status = 'DESIGN_PENDING_APPROVAL' WHERE id = NEW.crm_deal_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_design_task_completion_trigger ON public.tasks;
CREATE TRIGGER crm_design_task_completion_trigger
BEFORE UPDATE OF status ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.enforce_crm_design_task_completion();

CREATE OR REPLACE FUNCTION public.decide_crm_design_task_approval(p_step_id uuid, p_decision text, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_step public.crm_design_task_approval_steps%ROWTYPE;
    v_task public.tasks%ROWTYPE;
    v_deal public.crm_deals%ROWTYPE;
    v_remaining integer;
    v_notification_id uuid;
BEGIN
    p_decision := UPPER(BTRIM(COALESCE(p_decision, '')));
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'Invalid approval decision'; END IF;
    IF p_decision = 'REJECTED' AND NULLIF(BTRIM(COALESCE(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'A rejection reason is required'; END IF;
    SELECT * INTO v_step FROM public.crm_design_task_approval_steps WHERE id = p_step_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Design approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;
    UPDATE public.crm_design_task_approval_steps SET status = p_decision, decision_note = NULLIF(BTRIM(p_note), ''), decided_at = now()
    WHERE id = p_step_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval has already been decided'; END IF;
    SELECT * INTO v_task FROM public.tasks WHERE id = v_step.task_id;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_step.deal_id;
    IF p_decision = 'REJECTED' THEN
        UPDATE public.tasks SET status = 'in_progress', completion_requested_by = NULL, completion_requested_at = NULL WHERE id = v_task.id;
        UPDATE public.crm_deals SET workflow_status = 'DESIGN_REJECTED' WHERE id = v_deal.id;
        SELECT id INTO v_notification_id FROM public.notifications
        WHERE task_id = v_task.id AND user_id = v_task.assignee_id
        ORDER BY created_at DESC LIMIT 1;
        IF v_notification_id IS NULL THEN
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            VALUES (v_task.assignee_id, 'CRM Design task rejected: ' || v_task.title || '. Reason: ' || BTRIM(p_note), 'crm_design_task_rejected', v_task.id, auth.uid(), '/?view=tasks', jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note)))
            RETURNING id INTO v_notification_id;
        ELSE
            UPDATE public.notifications
               SET message = 'CRM Design task rejected: ' || v_task.title || '. Reason: ' || BTRIM(p_note),
                   event_type = 'crm_design_task_rejected',
                   metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note))
             WHERE id = v_notification_id;
        END IF;
        INSERT INTO public.task_email_outbox(notification_id, task_id, recipient_id, recipient_email, subject, message, action_url, always_send)
        SELECT v_notification_id, v_task.id, profile.id, auth_user.email, 'CRM Design task needs changes: ' || v_task.title,
               'Reason: ' || BTRIM(p_note), '/?view=tasks', true
        FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE profile.id = v_task.assignee_id AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
    ELSE
        SELECT count(*) INTO v_remaining FROM public.crm_design_task_approval_steps WHERE task_id = v_task.id AND status <> 'APPROVED';
        IF v_remaining = 0 THEN
            PERFORM set_config('app.crm_design_task_finalize', 'on', true);
            UPDATE public.tasks SET status = 'completed', completion_approved_by = auth.uid(), completion_approved_at = now() WHERE id = v_task.id;
            UPDATE public.crm_deals SET stage = 'NEGOTIATION', workflow_status = 'APPROVED' WHERE id = v_deal.id;
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            SELECT recipient, 'CRM Design approved and deal moved to Discussion: ' || v_deal.title,
                   'crm_design_task_approved', v_task.id, auth.uid(), '/?view=crm', jsonb_build_object('deal_id', v_deal.id)
            FROM unnest(array_remove(ARRAY[v_task.assignee_id, COALESCE(v_deal.created_by, v_deal.assigned_to)], NULL)) recipient;
        END IF;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_project_from_won_deal_v2(p_deal_id uuid, p_order jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_project_id uuid;
    v_assigned uuid[];
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deal not found'; END IF;
    IF v_deal.workflow_status <> 'APPROVED' THEN RAISE EXCEPTION 'Complete the deal workflow before opening the project'; END IF;
    IF auth.uid() NOT IN (COALESCE(v_deal.created_by, auth.uid()), COALESCE(v_deal.assigned_to, auth.uid()))
       AND NOT public.is_crm_approval_admin(auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND UPPER(COALESCE(p.role, '')) = 'MANAGER') THEN
        RAISE EXCEPTION 'Only the deal team or management can open this project';
    END IF;
    SELECT COALESCE(array_agg(value::uuid), '{}') INTO v_assigned
    FROM jsonb_array_elements_text(COALESCE(p_order->'assigned_people', '[]'::jsonb)) value;
    IF NULLIF(BTRIM(COALESCE(p_order->>'event_date', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->>'event_start_time', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->'client'->>'name', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->>'installation_type', '')), '') IS NULL THEN
        RAISE EXCEPTION 'Event date, starting time, client name, and installation type are required';
    END IF;
    IF COALESCE(array_length(v_assigned, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one Operations employee';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(v_assigned) assignee_id
        LEFT JOIN public.profiles profile ON profile.id = assignee_id
        LEFT JOIN public.departments department ON department.id = profile.department_id
        WHERE profile.id IS NULL OR profile.is_active IS FALSE
           OR NOT (
               COALESCE(department.name, '') ~* '(operation|operations|العمليات)'
               OR COALESCE(profile.job_title, '') ~* '(operation|operations|العمليات)'
           )
    ) THEN
        RAISE EXCEPTION 'Projects can only be assigned to Operations employees';
    END IF;
    IF jsonb_typeof(COALESCE(p_order->'equipment', '[]'::jsonb)) <> 'array'
       OR jsonb_array_length(COALESCE(p_order->'equipment', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Add at least one equipment item';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(p_order->'equipment', '[]'::jsonb)) equipment_item
        WHERE NULLIF(BTRIM(COALESCE(equipment_item->>'item', '')), '') IS NULL
           OR NULLIF(BTRIM(COALESCE(equipment_item->>'quantity', '')), '') IS NULL
    ) THEN
        RAISE EXCEPTION 'Every equipment item needs an item name and quantity';
    END IF;

    SELECT id INTO v_project_id FROM public.projects WHERE deal_id = p_deal_id ORDER BY created_at LIMIT 1 FOR UPDATE;
    IF v_project_id IS NULL THEN
        INSERT INTO public.projects(
            project_name, project_type, description, assigned_people, project_tags,
            deal_id, client_id, event_date, start_date, event_location, project_amount,
            paid_amount, project_status, source, order_employee_id, event_start_time,
            installation_time, uninstallation_time, client_snapshot, event_location_text,
            installation_type, equipment
        ) VALUES (
            v_deal.title, 'Client', NULLIF(p_order->>'notes', ''), v_assigned, ARRAY['Won Deal']::text[],
            v_deal.id, v_deal.client_id, (p_order->>'event_date')::date, (p_order->>'event_date')::date,
            NULLIF(p_order->>'location_url', ''), COALESCE(NULLIF(p_order->>'project_amount', '')::numeric, v_deal.amount, 0),
            COALESCE(NULLIF(p_order->>'paid_amount', '')::numeric, 0), 'Not Confirmed', 'WON_DEAL',
            COALESCE(v_deal.created_by, v_deal.assigned_to), (p_order->>'event_start_time')::time,
            NULLIF(p_order->>'installation_time', '')::time, NULLIF(p_order->>'uninstallation_time', '')::time,
            p_order->'client', NULLIF(p_order->>'location_text', ''),
            p_order->>'installation_type', p_order->'equipment'
        ) RETURNING id INTO v_project_id;
    ELSE
        UPDATE public.projects SET
            description = NULLIF(p_order->>'notes', ''), assigned_people = v_assigned,
            event_date = (p_order->>'event_date')::date, start_date = (p_order->>'event_date')::date,
            event_location = NULLIF(p_order->>'location_url', ''),
            project_amount = COALESCE(NULLIF(p_order->>'project_amount', '')::numeric, v_deal.amount, 0),
            paid_amount = COALESCE(NULLIF(p_order->>'paid_amount', '')::numeric, 0),
            order_employee_id = COALESCE(v_deal.created_by, v_deal.assigned_to),
            event_start_time = (p_order->>'event_start_time')::time,
            installation_time = NULLIF(p_order->>'installation_time', '')::time,
            uninstallation_time = NULLIF(p_order->>'uninstallation_time', '')::time,
            client_snapshot = p_order->'client', event_location_text = NULLIF(p_order->>'location_text', ''),
            installation_type = p_order->>'installation_type', equipment = p_order->'equipment'
        WHERE id = v_project_id;
    END IF;
    UPDATE public.crm_deals SET stage = 'WON' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (p_deal_id, 'PROJECT_CREATED', v_deal.stage, 'WON', NULLIF(p_order->>'notes', ''), auth.uid());
    RETURN v_project_id;
END;
$$;

REVOKE ALL ON FUNCTION public.start_crm_presentation_approval(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_deal_approval(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_crm_design_task_approval(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_project_from_won_deal_v2(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_crm_presentation_approval(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_deal_approval(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_crm_design_task_approval(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_project_from_won_deal_v2(uuid, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
