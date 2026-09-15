-- Keep the presentation-approval RPC aligned with the CRM access policy and
-- repair completion-audit columns that older production installs can miss.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS completion_requested_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completion_requested_at timestamptz,
    ADD COLUMN IF NOT EXISTS completion_approved_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completion_approved_at timestamptz;

CREATE OR REPLACE FUNCTION public.start_crm_presentation_approval(p_deal_id uuid, p_request_type text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

    SELECT * INTO v_deal
      FROM public.crm_deals
     WHERE id = p_deal_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deal not found';
    END IF;

    -- The CRM RLS policy already grants Sales, Marketing, CEO, GM and admin
    -- users access through can_access_crm(). The previous role-only check
    -- rejected regular Sales/Marketing users after their files were uploaded.
    IF NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You do not have access to start CRM approvals'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.crm_deal_attachments
         WHERE deal_id = p_deal_id AND category = 'QUOTATION'
    ) THEN
        RAISE EXCEPTION 'Upload a quote document first';
    END IF;
    IF p_request_type = 'QUOTE_PROPOSAL'
       AND NOT EXISTS (
           SELECT 1 FROM public.crm_deal_attachments
            WHERE deal_id = p_deal_id AND category = 'PROPOSAL'
       ) THEN
        RAISE EXCEPTION 'Upload at least one proposal image first';
    END IF;

    SELECT id INTO v_ceo
      FROM public.profiles
     WHERE is_active IS DISTINCT FROM false
       AND (
           UPPER(BTRIM(COALESCE(role, ''))) = 'CEO'
           OR UPPER(COALESCE(job_title, '')) ~ '(^|[^A-Z])(CEO|CHIEF EXECUTIVE)([^A-Z]|$)'
       )
     ORDER BY emp_index NULLS LAST
     LIMIT 1;

    SELECT id INTO v_gm
      FROM public.profiles
     WHERE is_active IS DISTINCT FROM false
       AND (
           UPPER(BTRIM(COALESCE(role, ''))) IN ('GM', 'GENERAL MANAGER')
           OR UPPER(COALESCE(job_title, '')) ~ '(^|[^A-Z])(GM|GENERAL MANAGER)([^A-Z]|$)'
       )
     ORDER BY emp_index NULLS LAST
     LIMIT 1;

    SELECT id INTO v_marketing
      FROM public.profiles
     WHERE is_active IS DISTINCT FROM false
       AND (
           UPPER(COALESCE(job_title, '')) ~ 'MARKETING.*MANAGER|MANAGER.*MARKETING'
           OR COALESCE(job_title, '') ~ 'مدير.*التسويق'
       )
     ORDER BY emp_index NULLS LAST
     LIMIT 1;

    SELECT id INTO v_mq04
      FROM public.profiles
     WHERE emp_index = 4 AND is_active IS DISTINCT FROM false
     LIMIT 1;

    SELECT id INTO v_mq05
      FROM public.profiles
     WHERE emp_index = 5 AND is_active IS DISTINCT FROM false
     LIMIT 1;

    IF v_ceo IS NULL OR v_gm IS NULL OR v_marketing IS NULL THEN
        RAISE EXCEPTION 'CEO, GM, and Marketing Manager accounts must be configured';
    END IF;
    IF p_request_type = 'QUOTE_PROPOSAL' AND (v_mq04 IS NULL OR v_mq05 IS NULL) THEN
        RAISE EXCEPTION 'Employee MQ-04 and MQ-05 accounts must be configured';
    END IF;

    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;
    INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
    VALUES
        (p_deal_id, 1, 'CEO', v_ceo),
        (p_deal_id, 2, 'GENERAL_MANAGER', v_gm);

    IF p_request_type = 'QUOTE_PROPOSAL' THEN
        INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
        VALUES
            (p_deal_id, 3, 'MQ_04', v_mq04),
            (p_deal_id, 4, 'MQ_05', v_mq05),
            (p_deal_id, 5, 'MARKETING_MANAGER', v_marketing);
    ELSE
        INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
        VALUES (p_deal_id, 3, 'MARKETING_MANAGER', v_marketing);
    END IF;

    UPDATE public.crm_deals
       SET stage = 'PITCH',
           approval_type = p_request_type,
           workflow_status = 'PENDING_APPROVAL',
           proposal_sent_at = now()
     WHERE id = p_deal_id;

    INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
    SELECT
        step.approver_id,
        CASE
            WHEN p_request_type = 'QUOTE' THEN 'Quote approval requested: '
            ELSE 'Quote and proposal approval requested: '
        END || COALESCE(v_deal.title, 'Untitled deal'),
        'crm_approval_requested',
        auth.uid(),
        '/?view=approvals',
        jsonb_build_object(
            'deal_id', p_deal_id,
            'step_id', step.id,
            'stage_key', step.stage_key,
            'request_type', p_request_type
        )
      FROM public.crm_deal_approval_steps step
     WHERE step.deal_id = p_deal_id;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (
        p_deal_id,
        'PRESENTATION_APPROVAL_STARTED',
        v_deal.stage,
        'PITCH',
        p_request_type,
        auth.uid()
    );
END;
$$;

REVOKE ALL ON FUNCTION public.start_crm_presentation_approval(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_crm_presentation_approval(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
