-- Keep quote-and-proposal deals in Presentation while MQ-08 completes Design,
-- track the Design task badge, and use the approval submission timestamp.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.crm_deals
    ADD COLUMN IF NOT EXISTS design_task_status text,
    ADD COLUMN IF NOT EXISTS design_task_due_date date;

ALTER TABLE public.crm_deals DROP CONSTRAINT IF EXISTS crm_deals_design_task_status_check;
ALTER TABLE public.crm_deals ADD CONSTRAINT crm_deals_design_task_status_check
    CHECK (design_task_status IS NULL OR design_task_status IN ('IN_PROGRESS', 'LATE', 'COMPLETED'));

CREATE OR REPLACE FUNCTION public.sync_crm_design_task_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_status text;
BEGIN
    IF NEW.crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL_DESIGN' OR NEW.crm_deal_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_status := CASE
        WHEN LOWER(BTRIM(COALESCE(NEW.status, ''))) IN ('completed', 'approved', 'pending approval') THEN 'COMPLETED'
        WHEN LOWER(BTRIM(COALESCE(NEW.status, ''))) = 'late' THEN 'LATE'
        WHEN NEW.due_date IS NOT NULL AND NEW.due_date < CURRENT_DATE THEN 'LATE'
        ELSE 'IN_PROGRESS'
    END;

    UPDATE public.crm_deals
       SET design_task_status = v_status,
           design_task_due_date = NEW.due_date
     WHERE id = NEW.crm_deal_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_design_task_status_insert_trigger ON public.tasks;
CREATE TRIGGER crm_design_task_status_insert_trigger
AFTER INSERT ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.sync_crm_design_task_status();

DROP TRIGGER IF EXISTS crm_design_task_status_update_trigger ON public.tasks;
CREATE TRIGGER crm_design_task_status_update_trigger
AFTER UPDATE OF status, due_date, crm_deal_id, crm_workflow_kind ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.sync_crm_design_task_status();

UPDATE public.crm_deals deal
   SET design_task_status = CASE
           WHEN LOWER(BTRIM(COALESCE(task.status, ''))) IN ('completed', 'approved', 'pending approval') THEN 'COMPLETED'
           WHEN LOWER(BTRIM(COALESCE(task.status, ''))) = 'late' THEN 'LATE'
           WHEN task.due_date IS NOT NULL AND task.due_date < CURRENT_DATE THEN 'LATE'
           ELSE 'IN_PROGRESS'
       END,
       design_task_due_date = task.due_date
  FROM public.tasks task
 WHERE task.id = deal.design_task_id
   AND task.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN';

CREATE OR REPLACE FUNCTION public.decide_deal_approval(p_step_id uuid, p_decision text, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_step public.crm_deal_approval_steps%ROWTYPE;
    v_deal public.crm_deals%ROWTYPE;
    v_remaining integer;
    v_owner uuid;
BEGIN
    p_decision := UPPER(BTRIM(COALESCE(p_decision, '')));
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'Invalid approval decision'; END IF;
    IF p_decision = 'REJECTED' AND NULLIF(BTRIM(COALESCE(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A rejection reason is required';
    END IF;

    SELECT * INTO v_step
      FROM public.crm_deal_approval_steps
     WHERE id = p_step_id
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;

    UPDATE public.crm_deal_approval_steps
       SET status = p_decision,
           decision_note = NULLIF(BTRIM(p_note), ''),
           decided_at = now()
     WHERE id = p_step_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval has already been decided'; END IF;

    SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_step.deal_id;
    v_owner := COALESCE(v_deal.created_by, v_deal.assigned_to);

    IF p_decision = 'REJECTED' THEN
        UPDATE public.crm_deals SET workflow_status = 'REJECTED' WHERE id = v_step.deal_id;
        IF v_owner IS NOT NULL THEN
            INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
            VALUES (
                v_owner,
                'CRM request rejected: ' || v_deal.title || '. Reason: ' || BTRIM(p_note),
                'crm_approval_rejected',
                auth.uid(),
                '/?view=crm',
                jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note), 'request_type', v_deal.approval_type)
            );
        END IF;
    ELSE
        SELECT count(*) INTO v_remaining
          FROM public.crm_deal_approval_steps
         WHERE deal_id = v_deal.id AND status <> 'APPROVED';

        IF v_remaining = 0 THEN
            IF v_deal.approval_type = 'QUOTE_PROPOSAL' THEN
                -- create_crm_design_task_for_deal requires APPROVED while it
                -- creates the task, then changes the status to DESIGN_IN_PROGRESS.
                UPDATE public.crm_deals
                   SET workflow_status = 'APPROVED',
                       stage = 'PITCH',
                       design_task_status = 'IN_PROGRESS'
                 WHERE id = v_deal.id;
                PERFORM public.create_crm_design_task_for_deal(v_deal.id);
            ELSE
                UPDATE public.crm_deals
                   SET workflow_status = 'APPROVED', stage = 'NEGOTIATION'
                 WHERE id = v_deal.id;
            END IF;

            IF v_owner IS NOT NULL THEN
                INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
                VALUES (
                    v_owner,
                    CASE WHEN v_deal.approval_type = 'QUOTE_PROPOSAL'
                         THEN 'CRM approval completed and Design task opened: '
                         ELSE 'CRM approval completed: ' END || v_deal.title,
                    'crm_approval_completed',
                    auth.uid(),
                    '/?view=crm',
                    jsonb_build_object('deal_id', v_deal.id, 'request_type', v_deal.approval_type)
                );
            END IF;
        END IF;
    END IF;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (v_deal.id, 'APPROVAL_DECISION', 'PENDING', p_decision, p_note, auth.uid());
END;
$$;

REVOKE ALL ON FUNCTION public.sync_crm_design_task_status() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decide_deal_approval(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_deal_approval(uuid, text, text) TO authenticated;

-- Repair quote-and-proposal deals that an earlier migration advanced before
-- their Design task was finished.
UPDATE public.crm_deals
   SET stage = 'PITCH'
 WHERE approval_type = 'QUOTE_PROPOSAL'
   AND design_task_id IS NOT NULL
   AND workflow_status IN ('DESIGN_IN_PROGRESS', 'DESIGN_PENDING_APPROVAL', 'DESIGN_REJECTED');

COMMIT;
