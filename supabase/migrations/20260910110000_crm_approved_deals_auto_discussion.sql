-- Advance fully approved CRM deals to Discussion immediately.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

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
            UPDATE public.crm_deals
               SET workflow_status = 'APPROVED', stage = 'NEGOTIATION'
             WHERE id = v_deal.id;

            IF v_deal.approval_type = 'QUOTE_PROPOSAL' THEN
                PERFORM public.create_crm_design_task_for_deal(v_deal.id);
            END IF;

            IF v_owner IS NOT NULL THEN
                INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
                VALUES (
                    v_owner,
                    'CRM approval completed: ' || v_deal.title,
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

REVOKE ALL ON FUNCTION public.decide_deal_approval(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_deal_approval(uuid, text, text) TO authenticated;

-- Repair deals whose approvals were completed before this behavior was added.
UPDATE public.crm_deals deal
   SET stage = 'NEGOTIATION', workflow_status = 'APPROVED'
 WHERE UPPER(COALESCE(deal.stage, '')) IN ('PITCH', 'PROPOSAL')
   AND EXISTS (
       SELECT 1 FROM public.crm_deal_approval_steps step
        WHERE step.deal_id = deal.id
   )
   AND NOT EXISTS (
       SELECT 1 FROM public.crm_deal_approval_steps step
        WHERE step.deal_id = deal.id
          AND UPPER(COALESCE(step.status, '')) <> 'APPROVED'
   );

COMMIT;
