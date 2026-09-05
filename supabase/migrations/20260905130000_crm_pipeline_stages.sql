-- Keep the CRM board, persisted deal stages, and approval workflow aligned with
-- the seven supported pipeline columns.
BEGIN;

UPDATE public.crm_deals
SET stage = CASE
    WHEN stage = 'QUOTATION' THEN 'QUALIFICATION'
    WHEN stage = 'TECHNICAL' THEN 'PITCH'
    WHEN stage = 'APPROVAL' AND workflow_status = 'APPROVED' THEN 'PROPOSAL'
    WHEN stage = 'APPROVAL' THEN 'PITCH'
    WHEN stage IS NULL OR stage NOT IN ('LEAD', 'QUALIFICATION', 'PITCH', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST') THEN 'LEAD'
    ELSE stage
END
WHERE stage IS NULL
   OR stage NOT IN ('LEAD', 'QUALIFICATION', 'PITCH', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST');

ALTER TABLE public.crm_deals
    DROP CONSTRAINT IF EXISTS crm_deals_stage_check;

ALTER TABLE public.crm_deals
    ALTER COLUMN stage SET NOT NULL;

ALTER TABLE public.crm_deals
    ADD CONSTRAINT crm_deals_stage_check
    CHECK (stage IN ('LEAD', 'QUALIFICATION', 'PITCH', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST'));

CREATE OR REPLACE FUNCTION public.start_deal_approval(
    p_deal_id UUID,
    p_marketing_manager UUID,
    p_general_manager UUID,
    p_operations_manager UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.crm_deals d
        WHERE d.id = p_deal_id AND (d.assigned_to = auth.uid() OR EXISTS (
            SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role IN ('ADMIN', 'MANAGER')
        ))
    ) THEN RAISE EXCEPTION 'Only the deal owner or a manager can start approval'; END IF;

    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;
    INSERT INTO public.crm_deal_approval_steps (deal_id, step_order, stage_key, approver_id)
    VALUES
        (p_deal_id, 1, 'MARKETING_MANAGER', p_marketing_manager),
        (p_deal_id, 2, 'GENERAL_MANAGER', p_general_manager),
        (p_deal_id, 3, 'OPERATIONS_MANAGER', p_operations_manager);
    UPDATE public.crm_deals SET workflow_status = 'PENDING_APPROVAL' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity (deal_id, action, to_status, actor_id)
    VALUES (p_deal_id, 'APPROVAL_STARTED', 'PENDING_APPROVAL', auth.uid());
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_deal_approval(UUID, UUID, UUID, UUID) TO authenticated;

COMMIT;
