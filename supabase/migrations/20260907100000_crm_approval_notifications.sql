-- Send actionable in-app notifications as a CRM deal moves through its
-- sequential Marketing, General Manager, and Operations approvals.
BEGIN;

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS event_type TEXT,
    ADD COLUMN IF NOT EXISTS actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS action_url TEXT,
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.start_deal_approval(
    p_deal_id UUID,
    p_marketing_manager UUID,
    p_general_manager UUID,
    p_operations_manager UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_first_step_id UUID;
BEGIN
    SELECT *
      INTO v_deal
      FROM public.crm_deals
     WHERE id = p_deal_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deal not found';
    END IF;

    IF v_deal.assigned_to IS DISTINCT FROM auth.uid()
       AND NOT EXISTS (
           SELECT 1
             FROM public.profiles profile
            WHERE profile.id = auth.uid()
              AND UPPER(COALESCE(profile.role, '')) IN ('ADMIN', 'MANAGER')
       ) THEN
        RAISE EXCEPTION 'Only the deal owner or a manager can start approval';
    END IF;

    IF p_marketing_manager IS NULL
       OR p_general_manager IS NULL
       OR p_operations_manager IS NULL THEN
        RAISE EXCEPTION 'All three approvers are required';
    END IF;

    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;

    INSERT INTO public.crm_deal_approval_steps (deal_id, step_order, stage_key, approver_id)
    VALUES (p_deal_id, 1, 'MARKETING_MANAGER', p_marketing_manager)
    RETURNING id INTO v_first_step_id;

    INSERT INTO public.crm_deal_approval_steps (deal_id, step_order, stage_key, approver_id)
    VALUES
        (p_deal_id, 2, 'GENERAL_MANAGER', p_general_manager),
        (p_deal_id, 3, 'OPERATIONS_MANAGER', p_operations_manager);

    UPDATE public.crm_deals
       SET workflow_status = 'PENDING_APPROVAL'
     WHERE id = p_deal_id;

    INSERT INTO public.crm_deal_activity (deal_id, action, to_status, actor_id)
    VALUES (p_deal_id, 'APPROVAL_STARTED', 'PENDING_APPROVAL', auth.uid());

    INSERT INTO public.notifications (
        user_id, message, event_type, actor_id, action_url, metadata
    ) VALUES (
        p_marketing_manager,
        'CRM approval requested: ' || COALESCE(NULLIF(BTRIM(v_deal.title), ''), 'Untitled deal'),
        'crm_approval_requested',
        auth.uid(),
        '/?view=crm',
        jsonb_build_object(
            'deal_id', p_deal_id,
            'step_id', v_first_step_id,
            'stage_key', 'MARKETING_MANAGER',
            'step_order', 1
        )
    );
END;
$$;

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
BEGIN
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN
        RAISE EXCEPTION 'Invalid approval decision';
    END IF;

    SELECT * INTO v_step
      FROM public.crm_deal_approval_steps
     WHERE id = p_step_id
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Approval step not found'; END IF;

    IF v_step.approver_id <> auth.uid()
       AND NOT EXISTS (
           SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND UPPER(COALESCE(role, '')) = 'ADMIN'
       ) THEN
        RAISE EXCEPTION 'Only the assigned approver can decide this step';
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

REVOKE ALL ON FUNCTION public.start_deal_approval(UUID, UUID, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.decide_deal_approval(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_deal_approval(UUID, UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_deal_approval(UUID, TEXT, TEXT) TO authenticated;

-- Repair workflows that were started before notifications were added. Only
-- the first currently actionable pending step receives a request.
INSERT INTO public.notifications (user_id, message, event_type, action_url, metadata)
SELECT
    step.approver_id,
    'CRM approval requested: ' || COALESCE(NULLIF(BTRIM(deal.title), ''), 'Untitled deal'),
    'crm_approval_requested',
    '/?view=crm',
    jsonb_build_object(
        'deal_id', deal.id,
        'step_id', step.id,
        'stage_key', step.stage_key,
        'step_order', step.step_order
    )
FROM public.crm_deals deal
JOIN public.crm_deal_approval_steps step ON step.deal_id = deal.id
WHERE deal.workflow_status = 'PENDING_APPROVAL'
  AND step.status = 'PENDING'
  AND NOT EXISTS (
      SELECT 1
      FROM public.crm_deal_approval_steps earlier
      WHERE earlier.deal_id = step.deal_id
        AND earlier.step_order < step.step_order
        AND earlier.status <> 'APPROVED'
  )
  AND NOT EXISTS (
      SELECT 1
      FROM public.notifications notification
      WHERE notification.event_type = 'crm_approval_requested'
        AND notification.metadata ->> 'step_id' = step.id::text
  );

NOTIFY pgrst, 'reload schema';
COMMIT;
