-- Hierarchical approval workflow for all employee requests.
-- Requires profiles, departments, notifications and task_email_outbox.
BEGIN;

CREATE TABLE IF NOT EXISTS public.request_approval_workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_table TEXT NOT NULL CHECK (source_table IN ('requests','leave_requests','document_requests','expenses')),
    source_id UUID NOT NULL,
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    request_type TEXT NOT NULL,
    is_financial BOOLEAN NOT NULL DEFAULT FALSE,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','REJECTED')),
    current_step INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    UNIQUE(source_table, source_id)
);

CREATE TABLE IF NOT EXISTS public.request_approval_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id UUID NOT NULL REFERENCES public.request_approval_workflows(id) ON DELETE CASCADE,
    step_order INTEGER NOT NULL,
    stage_key TEXT NOT NULL,
    approver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','REJECTED')),
    decision_note TEXT,
    decided_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(workflow_id, step_order)
);

CREATE INDEX IF NOT EXISTS request_workflow_employee_idx ON public.request_approval_workflows(employee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS request_steps_approver_idx ON public.request_approval_steps(approver_id, status);

ALTER TABLE public.request_approval_workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_approval_steps ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.queue_request_notification(p_user_id UUID, p_message TEXT, p_event_type TEXT, p_workflow_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE notification_row public.notifications%ROWTYPE; workflow_row public.request_approval_workflows%ROWTYPE;
BEGIN
    SELECT * INTO workflow_row FROM public.request_approval_workflows WHERE id=p_workflow_id;
    INSERT INTO public.notifications(user_id,message,event_type,action_url,metadata)
    VALUES(p_user_id,p_message,p_event_type,'/?view=requests',jsonb_build_object('workflow_id',p_workflow_id,'request_type',workflow_row.request_type,'source_table',workflow_row.source_table,'source_id',workflow_row.source_id))
    RETURNING * INTO notification_row;
    BEGIN
        INSERT INTO public.task_email_outbox(notification_id,recipient_id,recipient_email,subject,message,action_url)
        SELECT notification_row.id,profile.id,auth_user.email,'Request update: '||workflow_row.request_type,p_message,notification_row.action_url
        FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id=profile.id
        WHERE profile.id=p_user_id AND COALESCE(profile.task_email_notifications,TRUE)=TRUE AND NULLIF(BTRIM(auth_user.email),'') IS NOT NULL;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'Unable to queue request email: %',SQLERRM; END;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_request_approval_workflow(p_source_table TEXT,p_source_id UUID,p_employee_id UUID,p_request_type TEXT,p_is_financial BOOLEAN DEFAULT FALSE)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_workflow_id UUID; employee public.profiles%ROWTYPE; department_manager UUID; accountant_manager UUID; general_manager UUID; fallback_manager UUID;
DECLARE approvers UUID[] := '{}'; inserted_approvers UUID[] := '{}'; stages TEXT[] := '{}'; candidate UUID; stage TEXT; position INTEGER := 0; idx INTEGER;
BEGIN
    SELECT w.id INTO v_workflow_id FROM public.request_approval_workflows w WHERE w.source_table=p_source_table AND w.source_id=p_source_id;
    IF v_workflow_id IS NOT NULL THEN RETURN v_workflow_id; END IF;
    SELECT * INTO employee FROM public.profiles WHERE id=p_employee_id;
    SELECT head_id INTO department_manager FROM public.departments WHERE id=employee.department_id;
    SELECT id INTO accountant_manager FROM public.profiles WHERE is_active IS DISTINCT FROM FALSE AND (upper(COALESCE(job_title,'')) IN ('FINANCE MANAGER','ACCOUNTANT MANAGER') OR upper(COALESCE(role,''))='ACCOUNTANT_MANAGER') ORDER BY created_at LIMIT 1;
    IF accountant_manager IS NULL THEN SELECT head_id INTO accountant_manager FROM public.departments WHERE upper(name) IN ('ACCOUNTING','FINANCE') LIMIT 1; END IF;
    SELECT id INTO general_manager FROM public.profiles WHERE is_active IS DISTINCT FROM FALSE AND (upper(COALESCE(job_title,'')) LIKE '%GENERAL MANAGER%' OR upper(COALESCE(role,''))='GENERAL_MANAGER') ORDER BY created_at LIMIT 1;
    SELECT id INTO fallback_manager FROM public.profiles WHERE upper(COALESCE(role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN') ORDER BY created_at LIMIT 1;

    approvers := ARRAY[employee.manager_id,department_manager]; stages := ARRAY['SUPERVISOR_MANAGER','DEPARTMENT_MANAGER'];
    IF p_is_financial THEN
        IF accountant_manager IS NULL THEN RAISE EXCEPTION 'No Finance Manager is configured'; END IF;
        IF general_manager IS NULL THEN RAISE EXCEPTION 'No General Manager is configured'; END IF;
        approvers := approvers||ARRAY[accountant_manager,general_manager]; stages := stages||ARRAY['ACCOUNTANT_MANAGER','GENERAL_MANAGER'];
    END IF;
    INSERT INTO public.request_approval_workflows(source_table,source_id,employee_id,request_type,is_financial) VALUES(p_source_table,p_source_id,p_employee_id,p_request_type,p_is_financial) RETURNING id INTO v_workflow_id;
    FOR idx IN 1..array_length(approvers,1) LOOP
        candidate:=approvers[idx]; stage:=stages[idx];
        IF candidate IS NOT NULL AND candidate<>p_employee_id AND NOT candidate=ANY(inserted_approvers) THEN
            position:=position+1;
            INSERT INTO public.request_approval_steps(workflow_id,step_order,stage_key,approver_id) VALUES(v_workflow_id,position,stage,candidate);
            inserted_approvers:=array_append(inserted_approvers,candidate);
        END IF;
    END LOOP;
    IF position=0 AND fallback_manager IS NOT NULL THEN position:=1; INSERT INTO public.request_approval_steps(workflow_id,step_order,stage_key,approver_id) VALUES(v_workflow_id,1,'ADMIN_FALLBACK',fallback_manager); END IF;
    IF position=0 THEN RAISE EXCEPTION 'No approver is configured for this employee request'; END IF;
    SELECT approver_id INTO candidate FROM public.request_approval_steps WHERE workflow_id=v_workflow_id AND step_order=1;
    PERFORM public.queue_request_notification(candidate,'Approval required: '||p_request_type,'request_approval_required',v_workflow_id);
    PERFORM public.queue_request_notification(p_employee_id,'Your '||p_request_type||' request was submitted and is awaiting approval.','request_status_changed',v_workflow_id);
    RETURN v_workflow_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_request_approval(p_source_table TEXT,p_source_id UUID,p_decision TEXT,p_note TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE workflow public.request_approval_workflows%ROWTYPE; current_step public.request_approval_steps%ROWTYPE; next_step public.request_approval_steps%ROWTYPE; normalized TEXT; display_stage TEXT;
BEGIN
    normalized:=upper(p_decision); IF normalized NOT IN ('APPROVED','REJECTED') THEN RAISE EXCEPTION 'Decision must be APPROVED or REJECTED'; END IF;
    SELECT w.* INTO workflow FROM public.request_approval_workflows w WHERE w.source_table=p_source_table AND w.source_id=p_source_id FOR UPDATE;
    IF NOT FOUND OR workflow.status<>'PENDING' THEN RAISE EXCEPTION 'Request is not awaiting approval'; END IF;
    SELECT * INTO current_step FROM public.request_approval_steps WHERE workflow_id=workflow.id AND step_order=workflow.current_step FOR UPDATE;
    IF current_step.approver_id<>auth.uid() THEN RAISE EXCEPTION 'This request is awaiting approval from another manager' USING ERRCODE='42501'; END IF;
    UPDATE public.request_approval_steps SET status=normalized,decision_note=p_note,decided_at=now() WHERE id=current_step.id;
    display_stage:=initcap(replace(current_step.stage_key,'_',' '));
    IF normalized='REJECTED' THEN
        UPDATE public.request_approval_workflows SET status='REJECTED',completed_at=now() WHERE id=workflow.id;
        EXECUTE format('UPDATE public.%I SET status=$1 WHERE id=$2',workflow.source_table) USING 'REJECTED',workflow.source_id;
        PERFORM public.queue_request_notification(workflow.employee_id,'Your '||workflow.request_type||' request was rejected by '||display_stage||COALESCE(': '||NULLIF(p_note,''),'.'),'request_rejected',workflow.id);
        RETURN jsonb_build_object('status','REJECTED');
    END IF;
    SELECT * INTO next_step FROM public.request_approval_steps WHERE workflow_id=workflow.id AND step_order=workflow.current_step+1;
    IF FOUND THEN
        UPDATE public.request_approval_workflows SET current_step=current_step.step_order+1 WHERE id=workflow.id;
        PERFORM public.queue_request_notification(next_step.approver_id,'Approval required: '||workflow.request_type,'request_approval_required',workflow.id);
        PERFORM public.queue_request_notification(workflow.employee_id,'Your '||workflow.request_type||' request was approved by '||display_stage||' and moved to the next approval stage.','request_status_changed',workflow.id);
        RETURN jsonb_build_object('status','PENDING','current_step',next_step.step_order,'stage',next_step.stage_key);
    END IF;
    UPDATE public.request_approval_workflows SET status='APPROVED',completed_at=now() WHERE id=workflow.id;
    EXECUTE format('UPDATE public.%I SET status=$1 WHERE id=$2',workflow.source_table) USING 'APPROVED',workflow.source_id;
    PERFORM public.queue_request_notification(workflow.employee_id,'Your '||workflow.request_type||' request received final approval.','request_approved',workflow.id);
    RETURN jsonb_build_object('status','APPROVED');
END;
$$;

CREATE OR REPLACE FUNCTION public.request_workflow_after_insert() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE req_type TEXT; financial BOOLEAN;
BEGIN
    IF TG_TABLE_NAME='leave_requests' THEN req_type:='Leave - '||NEW.leave_type;
    ELSIF TG_TABLE_NAME='document_requests' THEN req_type:=NEW.doc_type;
    ELSIF TG_TABLE_NAME='expenses' THEN req_type:='Expense / Item Purchase';
    ELSE
        req_type:=NEW.request_type;
        IF lower(COALESCE(NEW.request_type,'')) ~ '^loan( request)?$' AND NEW.loan_amount IS NOT NULL THEN
            req_type:=NEW.request_type||' - '||to_char(NEW.loan_amount,'FM999G999G999G990D00')||' SAR';
        END IF;
    END IF;
    financial:=lower(req_type) ~ '(loan|pay[ -]?slip|item purchase|purchase|expense)';
    PERFORM public.start_request_approval_workflow(TG_TABLE_NAME,NEW.id,NEW.employee_id,req_type,financial);
    RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS request_workflow_leave_insert ON public.leave_requests; CREATE TRIGGER request_workflow_leave_insert AFTER INSERT ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.request_workflow_after_insert();
DROP TRIGGER IF EXISTS request_workflow_document_insert ON public.document_requests; CREATE TRIGGER request_workflow_document_insert AFTER INSERT ON public.document_requests FOR EACH ROW EXECUTE FUNCTION public.request_workflow_after_insert();
DROP TRIGGER IF EXISTS request_workflow_expense_insert ON public.expenses; CREATE TRIGGER request_workflow_expense_insert AFTER INSERT ON public.expenses FOR EACH ROW EXECUTE FUNCTION public.request_workflow_after_insert();
DROP TRIGGER IF EXISTS request_workflow_generic_insert ON public.requests; CREATE TRIGGER request_workflow_generic_insert AFTER INSERT ON public.requests FOR EACH ROW EXECUTE FUNCTION public.request_workflow_after_insert();

-- Bring existing pending requests into the same hierarchy without stopping the
-- migration when an older employee record still needs its managers configured.
DO $$
DECLARE item RECORD;
BEGIN
    FOR item IN
        SELECT 'leave_requests'::TEXT source_table,id,employee_id,('Leave - '||leave_type)::TEXT request_type FROM public.leave_requests WHERE upper(status)='PENDING'
        UNION ALL
        SELECT 'document_requests',id,employee_id,doc_type FROM public.document_requests WHERE upper(status)='PENDING'
        UNION ALL
        SELECT 'expenses',id,employee_id,'Expense / Item Purchase' FROM public.expenses WHERE upper(status)='PENDING'
        UNION ALL
        SELECT 'requests',id,employee_id,COALESCE(request_type,'Employee Request') FROM public.requests WHERE upper(status)='PENDING'
    LOOP
        BEGIN
            PERFORM public.start_request_approval_workflow(
                item.source_table,item.id,item.employee_id,item.request_type,
                lower(item.request_type) ~ '(loan|pay[ -]?slip|item purchase|purchase|expense)'
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Pending request % could not be added to its workflow: %',item.id,SQLERRM;
        END;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_view_request_workflow(p_workflow_id UUID,p_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
    SELECT EXISTS(
        SELECT 1 FROM public.request_approval_workflows w
        WHERE w.id=p_workflow_id AND (
            w.employee_id=p_user_id OR
            EXISTS(SELECT 1 FROM public.request_approval_steps s WHERE s.workflow_id=w.id AND s.approver_id=p_user_id) OR
            EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=p_user_id AND upper(COALESCE(p.role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN'))
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.is_request_workflow_approver(p_source_table TEXT,p_source_id UUID,p_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
    SELECT EXISTS(
        SELECT 1 FROM public.request_approval_workflows w
        JOIN public.request_approval_steps s ON s.workflow_id=w.id
        WHERE w.source_table=p_source_table AND w.source_id=p_source_id AND s.approver_id=p_user_id
    );
$$;

DROP POLICY IF EXISTS request_workflows_visible ON public.request_approval_workflows;
CREATE POLICY request_workflows_visible ON public.request_approval_workflows FOR SELECT TO authenticated USING(public.can_view_request_workflow(id,auth.uid()));
DROP POLICY IF EXISTS request_steps_visible ON public.request_approval_steps;
CREATE POLICY request_steps_visible ON public.request_approval_steps FOR SELECT TO authenticated USING(public.can_view_request_workflow(workflow_id,auth.uid()));

DROP POLICY IF EXISTS request_workflow_approver_leave_select ON public.leave_requests;
CREATE POLICY request_workflow_approver_leave_select ON public.leave_requests FOR SELECT TO authenticated USING(public.is_request_workflow_approver('leave_requests',id,auth.uid()));
DROP POLICY IF EXISTS request_workflow_approver_document_select ON public.document_requests;
CREATE POLICY request_workflow_approver_document_select ON public.document_requests FOR SELECT TO authenticated USING(public.is_request_workflow_approver('document_requests',id,auth.uid()));
DROP POLICY IF EXISTS request_workflow_approver_expense_select ON public.expenses;
CREATE POLICY request_workflow_approver_expense_select ON public.expenses FOR SELECT TO authenticated USING(public.is_request_workflow_approver('expenses',id,auth.uid()));
DROP POLICY IF EXISTS request_workflow_approver_generic_select ON public.requests;
CREATE POLICY request_workflow_approver_generic_select ON public.requests FOR SELECT TO authenticated USING(public.is_request_workflow_approver('requests',id,auth.uid()));

GRANT EXECUTE ON FUNCTION public.decide_request_approval(TEXT,UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_request_workflow(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_request_workflow_approver(TEXT,UUID,UUID) TO authenticated;
GRANT SELECT ON public.request_approval_workflows,public.request_approval_steps TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
