-- Allow every recognized application administrator role to approve or reject
-- the currently actionable CRM approval step, while preserving step order.
BEGIN;

CREATE OR REPLACE FUNCTION public.decide_deal_approval(
    p_step_id UUID,
    p_decision TEXT,
    p_note TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_step public.crm_deal_approval_steps%ROWTYPE;
    v_next_step public.crm_deal_approval_steps%ROWTYPE;
    v_deal public.crm_deals%ROWTYPE;
    v_prior_pending INTEGER;
    v_remaining INTEGER;
    v_actor_is_admin BOOLEAN;
BEGIN
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN
        RAISE EXCEPTION 'Invalid approval decision';
    END IF;

    SELECT EXISTS (
        SELECT 1
          FROM public.profiles profile
         WHERE profile.id = auth.uid()
           AND UPPER(BTRIM(COALESCE(profile.role, ''))) IN (
               'ADMIN', 'OWNER', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'
           )
    ) INTO v_actor_is_admin;

    SELECT * INTO v_step
      FROM public.crm_deal_approval_steps
     WHERE id = p_step_id
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Approval step not found'; END IF;

    IF v_step.approver_id <> auth.uid() AND NOT v_actor_is_admin THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this step';
    END IF;

    SELECT count(*) INTO v_prior_pending
      FROM public.crm_deal_approval_steps
     WHERE deal_id = v_step.deal_id
       AND step_order < v_step.step_order
       AND status <> 'APPROVED';
    IF v_prior_pending > 0 THEN
        RAISE EXCEPTION 'Previous approval steps must be completed first';
    END IF;

    UPDATE public.crm_deal_approval_steps
       SET status = p_decision,
           decision_note = NULLIF(BTRIM(p_note), ''),
           decided_at = now()
     WHERE id = p_step_id
       AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval step has already been decided'; END IF;

    SELECT * INTO v_deal
      FROM public.crm_deals
     WHERE id = v_step.deal_id;

    IF p_decision = 'REJECTED' THEN
        UPDATE public.crm_deals
           SET workflow_status = 'REJECTED'
         WHERE id = v_step.deal_id;

        IF v_deal.assigned_to IS NOT NULL AND v_deal.assigned_to IS DISTINCT FROM auth.uid() THEN
            INSERT INTO public.notifications (user_id, message, event_type, actor_id, action_url, metadata)
            VALUES (
                v_deal.assigned_to,
                'CRM approval rejected: ' || COALESCE(NULLIF(BTRIM(v_deal.title), ''), 'Untitled deal'),
                'crm_approval_rejected',
                auth.uid(),
                '/?view=crm',
                jsonb_build_object('deal_id', v_step.deal_id, 'step_id', v_step.id, 'stage_key', v_step.stage_key)
            );
        END IF;
    ELSE
        SELECT count(*) INTO v_remaining
          FROM public.crm_deal_approval_steps
         WHERE deal_id = v_step.deal_id
           AND status <> 'APPROVED';

        IF v_remaining = 0 THEN
            UPDATE public.crm_deals
               SET workflow_status = 'APPROVED'
             WHERE id = v_step.deal_id;

            IF v_deal.assigned_to IS NOT NULL AND v_deal.assigned_to IS DISTINCT FROM auth.uid() THEN
                INSERT INTO public.notifications (user_id, message, event_type, actor_id, action_url, metadata)
                VALUES (
                    v_deal.assigned_to,
                    'CRM approval completed: ' || COALESCE(NULLIF(BTRIM(v_deal.title), ''), 'Untitled deal'),
                    'crm_approval_completed',
                    auth.uid(),
                    '/?view=crm',
                    jsonb_build_object('deal_id', v_step.deal_id)
                );
            END IF;
        ELSE
            SELECT * INTO v_next_step
              FROM public.crm_deal_approval_steps
             WHERE deal_id = v_step.deal_id
               AND status = 'PENDING'
             ORDER BY step_order
             LIMIT 1;

            INSERT INTO public.notifications (user_id, message, event_type, actor_id, action_url, metadata)
            VALUES (
                v_next_step.approver_id,
                'CRM approval requested: ' || COALESCE(NULLIF(BTRIM(v_deal.title), ''), 'Untitled deal'),
                'crm_approval_requested',
                auth.uid(),
                '/?view=crm',
                jsonb_build_object(
                    'deal_id', v_step.deal_id,
                    'step_id', v_next_step.id,
                    'stage_key', v_next_step.stage_key,
                    'step_order', v_next_step.step_order
                )
            );
        END IF;
    END IF;

    INSERT INTO public.crm_deal_activity (deal_id, action, from_status, to_status, note, actor_id)
    VALUES (v_step.deal_id, 'APPROVAL_DECISION', 'PENDING', p_decision, p_note, auth.uid());
END;
$$;

REVOKE ALL ON FUNCTION public.decide_deal_approval(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.decide_deal_approval(UUID, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
