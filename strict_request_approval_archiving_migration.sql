-- Enforce sequential request approvals and archive immediately on rejection.
BEGIN;

ALTER TABLE public.request_approval_workflows
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS rejected_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

ALTER TABLE public.requests ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.requests ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;
ALTER TABLE public.requests ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE public.leave_requests ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.leave_requests ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;
ALTER TABLE public.leave_requests ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE public.document_requests ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.document_requests ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;
ALTER TABLE public.document_requests ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

CREATE INDEX IF NOT EXISTS requests_archived_idx ON public.requests(is_archived,archived_at DESC);
CREATE INDEX IF NOT EXISTS leave_requests_archived_idx ON public.leave_requests(is_archived,archived_at DESC);
CREATE INDEX IF NOT EXISTS document_requests_archived_idx ON public.document_requests(is_archived,archived_at DESC);
CREATE INDEX IF NOT EXISTS expenses_archived_idx ON public.expenses(is_archived,archived_at DESC);

CREATE OR REPLACE FUNCTION public.decide_request_approval(p_source_table TEXT,p_source_id UUID,p_decision TEXT,p_note TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
    workflow public.request_approval_workflows%ROWTYPE;
    current_step public.request_approval_steps%ROWTYPE;
    next_step public.request_approval_steps%ROWTYPE;
    normalized TEXT;
    clean_note TEXT;
    display_stage TEXT;
    actor_is_admin BOOLEAN;
BEGIN
    normalized:=UPPER(BTRIM(COALESCE(p_decision,'')));
    clean_note:=NULLIF(BTRIM(COALESCE(p_note,'')),'');
    IF normalized NOT IN ('APPROVED','REJECTED') THEN RAISE EXCEPTION 'Decision must be APPROVED or REJECTED'; END IF;
    IF normalized='REJECTED' AND clean_note IS NULL THEN RAISE EXCEPTION 'A rejection reason is required'; END IF;

    SELECT EXISTS(
        SELECT 1 FROM public.profiles
        WHERE id=auth.uid()
          AND UPPER(COALESCE(role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
    ) INTO actor_is_admin;

    SELECT * INTO workflow FROM public.request_approval_workflows
    WHERE source_table=p_source_table AND source_id=p_source_id FOR UPDATE;
    IF NOT FOUND OR workflow.status<>'PENDING' OR workflow.archived_at IS NOT NULL THEN
        RAISE EXCEPTION 'Request is not awaiting approval';
    END IF;

    SELECT * INTO current_step FROM public.request_approval_steps
    WHERE workflow_id=workflow.id AND step_order=workflow.current_step FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'The active approval stage is missing'; END IF;
    IF current_step.approver_id<>auth.uid() AND NOT actor_is_admin THEN
        RAISE EXCEPTION 'This request is awaiting approval from another manager' USING ERRCODE='42501';
    END IF;
    IF current_step.status<>'PENDING' THEN RAISE EXCEPTION 'This approval stage has already been decided'; END IF;
    IF EXISTS(SELECT 1 FROM public.request_approval_steps WHERE workflow_id=workflow.id AND step_order<current_step.step_order AND status<>'APPROVED') THEN
        RAISE EXCEPTION 'A previous approval stage has not been approved';
    END IF;

    UPDATE public.request_approval_steps
    SET status=normalized,decision_note=clean_note,decided_at=NOW()
    WHERE id=current_step.id;
    display_stage:=INITCAP(REPLACE(current_step.stage_key,'_',' '));

    IF normalized='REJECTED' THEN
        UPDATE public.request_approval_workflows
        SET status='REJECTED',completed_at=NOW(),archived_at=NOW(),rejected_by=auth.uid(),rejection_reason=clean_note
        WHERE id=workflow.id;
        EXECUTE format('UPDATE public.%I SET status=$1,is_archived=TRUE,archived_at=NOW(),rejection_reason=$2 WHERE id=$3',workflow.source_table)
        USING 'REJECTED',clean_note,workflow.source_id;
        PERFORM public.queue_request_notification(workflow.employee_id,
            'Your '||workflow.request_type||' request was rejected by '||display_stage||'. Reason: '||clean_note||' The request has been archived.',
            'request_rejected',workflow.id);
        RETURN jsonb_build_object('status','REJECTED','archived',TRUE,'reason',clean_note);
    END IF;

    SELECT * INTO next_step FROM public.request_approval_steps
    WHERE workflow_id=workflow.id AND step_order=current_step.step_order+1;
    IF FOUND THEN
        UPDATE public.request_approval_workflows SET current_step=next_step.step_order WHERE id=workflow.id;
        PERFORM public.queue_request_notification(next_step.approver_id,'Approval required: '||workflow.request_type,'request_approval_required',workflow.id);
        PERFORM public.queue_request_notification(workflow.employee_id,
            'Your '||workflow.request_type||' request was approved by '||display_stage||' and moved to '||INITCAP(REPLACE(next_step.stage_key,'_',' '))||'.',
            'request_status_changed',workflow.id);
        RETURN jsonb_build_object('status','PENDING','current_step',next_step.step_order,'stage',next_step.stage_key);
    END IF;

    UPDATE public.request_approval_workflows SET status='APPROVED',completed_at=NOW() WHERE id=workflow.id;
    EXECUTE format('UPDATE public.%I SET status=$1 WHERE id=$2',workflow.source_table) USING 'APPROVED',workflow.source_id;
    PERFORM public.queue_request_notification(workflow.employee_id,'Your '||workflow.request_type||' request received final approval.','request_approved',workflow.id);
    RETURN jsonb_build_object('status','APPROVED');
END; $$;

REVOKE ALL ON FUNCTION public.decide_request_approval(TEXT,UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.decide_request_approval(TEXT,UUID,TEXT,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
