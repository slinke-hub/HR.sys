-- Deal workflow, approvals, attachments and won-project details.
-- Safe to run repeatedly.

ALTER TABLE public.crm_deals
    ADD COLUMN IF NOT EXISTS workflow_status TEXT NOT NULL DEFAULT 'NOT_STARTED',
    ADD COLUMN IF NOT EXISTS technical_description TEXT,
    ADD COLUMN IF NOT EXISTS proposal_sent_at TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS lost_reason TEXT;

ALTER TABLE public.crm_orders
    ADD COLUMN IF NOT EXISTS event_date DATE,
    ADD COLUMN IF NOT EXISTS paid_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS uninstallation_date DATE;

CREATE TABLE IF NOT EXISTS public.crm_deal_approval_steps (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    deal_id UUID NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    step_order INTEGER NOT NULL CHECK (step_order BETWEEN 1 AND 3),
    stage_key TEXT NOT NULL CHECK (stage_key IN ('MARKETING_MANAGER', 'GENERAL_MANAGER', 'OPERATIONS_MANAGER')),
    approver_id UUID REFERENCES public.profiles(id),
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    decision_note TEXT,
    decided_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now()),
    UNIQUE (deal_id, step_order),
    UNIQUE (deal_id, stage_key)
);

CREATE TABLE IF NOT EXISTS public.crm_deal_attachments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    deal_id UUID NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    category TEXT NOT NULL DEFAULT 'OTHER' CHECK (category IN ('QUOTATION', 'TECHNICAL_PRESENTATION', 'PROPOSAL', 'PHOTO', 'OTHER')),
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,
    description TEXT,
    uploaded_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS public.crm_deal_activity (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    deal_id UUID NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    action TEXT NOT NULL,
    from_status TEXT,
    to_status TEXT,
    note TEXT,
    actor_id UUID REFERENCES public.profiles(id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS crm_deal_approval_steps_deal_idx ON public.crm_deal_approval_steps(deal_id, step_order);
CREATE INDEX IF NOT EXISTS crm_deal_attachments_deal_idx ON public.crm_deal_attachments(deal_id, created_at DESC);
CREATE INDEX IF NOT EXISTS crm_deal_activity_deal_idx ON public.crm_deal_activity(deal_id, created_at DESC);

ALTER TABLE public.crm_deal_approval_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_activity ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view deal approvals" ON public.crm_deal_approval_steps;
CREATE POLICY "Authenticated users can view deal approvals" ON public.crm_deal_approval_steps
    FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Authenticated users can manage deal approvals" ON public.crm_deal_approval_steps;

DROP POLICY IF EXISTS "Authenticated users can view deal attachments" ON public.crm_deal_attachments;
CREATE POLICY "Authenticated users can view deal attachments" ON public.crm_deal_attachments
    FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Authenticated users can add deal attachments" ON public.crm_deal_attachments;
CREATE POLICY "Authenticated users can add deal attachments" ON public.crm_deal_attachments
    FOR INSERT TO authenticated WITH CHECK (uploaded_by = auth.uid());
DROP POLICY IF EXISTS "Owners and admins can delete deal attachments" ON public.crm_deal_attachments;
CREATE POLICY "Owners and admins can delete deal attachments" ON public.crm_deal_attachments
    FOR DELETE TO authenticated USING (
        uploaded_by = auth.uid() OR EXISTS (
            SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'ADMIN'
        )
    );

DROP POLICY IF EXISTS "Authenticated users can view deal activity" ON public.crm_deal_activity;
CREATE POLICY "Authenticated users can view deal activity" ON public.crm_deal_activity
    FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Authenticated users can add deal activity" ON public.crm_deal_activity;
CREATE POLICY "Authenticated users can add deal activity" ON public.crm_deal_activity
    FOR INSERT TO authenticated WITH CHECK (actor_id = auth.uid());

INSERT INTO storage.buckets (id, name, public)
VALUES ('crm-deal-files', 'crm-deal-files', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Authenticated users can upload CRM deal files" ON storage.objects;
CREATE POLICY "Authenticated users can upload CRM deal files" ON storage.objects
    FOR INSERT TO authenticated WITH CHECK (bucket_id = 'crm-deal-files');
DROP POLICY IF EXISTS "Anyone can read CRM deal files" ON storage.objects;
CREATE POLICY "Anyone can read CRM deal files" ON storage.objects
    FOR SELECT USING (bucket_id = 'crm-deal-files');
DROP POLICY IF EXISTS "Owners and admins can delete CRM deal files" ON storage.objects;
CREATE POLICY "Owners and admins can delete CRM deal files" ON storage.objects
    FOR DELETE TO authenticated USING (
        bucket_id = 'crm-deal-files' AND (owner = auth.uid() OR EXISTS (
            SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'ADMIN'
        ))
    );

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
    UPDATE public.crm_deals SET stage = 'APPROVAL', workflow_status = 'PENDING_APPROVAL' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity (deal_id, action, to_status, actor_id)
    VALUES (p_deal_id, 'APPROVAL_STARTED', 'PENDING_APPROVAL', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_deal_approval(
    p_step_id UUID,
    p_decision TEXT,
    p_note TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_step public.crm_deal_approval_steps%ROWTYPE;
    v_prior_pending INTEGER;
    v_remaining INTEGER;
BEGIN
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN
        RAISE EXCEPTION 'Invalid approval decision';
    END IF;
    SELECT * INTO v_step FROM public.crm_deal_approval_steps WHERE id = p_step_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Approval step not found'; END IF;
    IF v_step.approver_id <> auth.uid() AND NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN'
    ) THEN RAISE EXCEPTION 'Only the assigned approver can decide this step'; END IF;
    SELECT count(*) INTO v_prior_pending FROM public.crm_deal_approval_steps
      WHERE deal_id = v_step.deal_id AND step_order < v_step.step_order AND status <> 'APPROVED';
    IF v_prior_pending > 0 THEN RAISE EXCEPTION 'Previous approval steps must be completed first'; END IF;
    UPDATE public.crm_deal_approval_steps
      SET status = p_decision, decision_note = NULLIF(trim(p_note), ''), decided_at = now()
      WHERE id = p_step_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval step has already been decided'; END IF;
    IF p_decision = 'REJECTED' THEN
        UPDATE public.crm_deals SET workflow_status = 'REJECTED' WHERE id = v_step.deal_id;
    ELSE
        SELECT count(*) INTO v_remaining FROM public.crm_deal_approval_steps
          WHERE deal_id = v_step.deal_id AND status <> 'APPROVED';
        IF v_remaining = 0 THEN
            UPDATE public.crm_deals SET workflow_status = 'APPROVED' WHERE id = v_step.deal_id;
        END IF;
    END IF;
    INSERT INTO public.crm_deal_activity (deal_id, action, from_status, to_status, note, actor_id)
    VALUES (v_step.deal_id, 'APPROVAL_DECISION', 'PENDING', p_decision, p_note, auth.uid());
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_deal_approval(UUID, UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_deal_approval(UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.stage IN ('PROPOSAL', 'NEGOTIATION', 'WON')
       AND COALESCE(NEW.workflow_status, 'NOT_STARTED') <> 'APPROVED' THEN
        RAISE EXCEPTION 'All internal deal approvals must be completed before this stage';
    END IF;
    IF NEW.stage = 'LOST' AND NULLIF(trim(COALESCE(NEW.lost_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A lost reason is required';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_deals_enforce_workflow_transition ON public.crm_deals;
CREATE TRIGGER crm_deals_enforce_workflow_transition
BEFORE INSERT OR UPDATE OF stage, workflow_status, lost_reason ON public.crm_deals
FOR EACH ROW EXECUTE FUNCTION public.enforce_deal_workflow_transition();
