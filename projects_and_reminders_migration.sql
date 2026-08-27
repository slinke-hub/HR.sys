-- Move won-deal delivery data into Projects and restore personal reminders.
-- Safe to run repeatedly after tasks_v4_migration.sql and deal_workflow_migration.sql.

ALTER TABLE public.projects
    ADD COLUMN IF NOT EXISTS deal_id UUID REFERENCES public.crm_deals(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS client_id UUID REFERENCES public.crm_clients(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS event_date DATE,
    ADD COLUMN IF NOT EXISTS start_date DATE,
    ADD COLUMN IF NOT EXISTS end_date DATE,
    ADD COLUMN IF NOT EXISTS uninstallation_date DATE,
    ADD COLUMN IF NOT EXISTS event_location TEXT,
    ADD COLUMN IF NOT EXISTS project_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS paid_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS project_status TEXT NOT NULL DEFAULT 'Not Confirmed',
    ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'MANUAL';

ALTER TABLE public.crm_orders
    ADD COLUMN IF NOT EXISTS event_date DATE,
    ADD COLUMN IF NOT EXISTS paid_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS uninstallation_date DATE;

CREATE UNIQUE INDEX IF NOT EXISTS projects_deal_id_unique_idx
    ON public.projects(deal_id) WHERE deal_id IS NOT NULL;

-- Preserve existing order records by representing each one as a project.
INSERT INTO public.projects (
    project_name, project_type, description, assigned_people, project_category, project_tags,
    deal_id, client_id, event_date, start_date, end_date, uninstallation_date,
    event_location, project_amount, paid_amount, project_status, source
)
SELECT
    d.title,
    'Client',
    o.notes,
    CASE WHEN d.assigned_to IS NULL THEN ARRAY[]::UUID[] ELSE ARRAY[d.assigned_to] END,
    NULL,
    ARRAY['Won Deal']::TEXT[],
    d.id,
    d.client_id,
    COALESCE(o.event_date, o.start_date),
    o.start_date,
    o.end_date,
    o.uninstallation_date,
    o.event_location,
    o.invoice_amount,
    o.paid_amount,
    o.project_status,
    'WON_DEAL'
FROM public.crm_orders o
JOIN public.crm_deals d ON d.id = o.deal_id
WHERE NOT EXISTS (SELECT 1 FROM public.projects p WHERE p.deal_id = d.id);

CREATE OR REPLACE FUNCTION public.create_project_from_won_deal(
    p_deal_id UUID,
    p_event_date DATE,
    p_start_date DATE,
    p_end_date DATE,
    p_uninstallation_date DATE,
    p_event_location TEXT,
    p_project_amount NUMERIC,
    p_paid_amount NUMERIC,
    p_project_status TEXT,
    p_notes TEXT
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_project_id UUID;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deal not found'; END IF;
    IF COALESCE(v_deal.workflow_status, 'NOT_STARTED') <> 'APPROVED' THEN
        RAISE EXCEPTION 'All internal approvals must be completed first';
    END IF;
    IF auth.uid() <> v_deal.assigned_to AND NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')
    ) THEN RAISE EXCEPTION 'Only the deal owner or a manager can create its project'; END IF;

    INSERT INTO public.projects (
        project_name, project_type, description, assigned_people, project_tags,
        deal_id, client_id, event_date, start_date, end_date, uninstallation_date,
        event_location, project_amount, paid_amount, project_status, source
    ) VALUES (
        v_deal.title, 'Client', p_notes,
        CASE WHEN v_deal.assigned_to IS NULL THEN ARRAY[]::UUID[] ELSE ARRAY[v_deal.assigned_to] END,
        ARRAY['Won Deal']::TEXT[], p_deal_id, v_deal.client_id, p_event_date,
        p_start_date, p_end_date, p_uninstallation_date, p_event_location,
        COALESCE(p_project_amount, v_deal.amount, 0), COALESCE(p_paid_amount, 0),
        COALESCE(NULLIF(p_project_status, ''), 'Not Confirmed'), 'WON_DEAL'
    )
    ON CONFLICT (deal_id) WHERE deal_id IS NOT NULL DO UPDATE SET
        event_date = EXCLUDED.event_date,
        start_date = EXCLUDED.start_date,
        end_date = EXCLUDED.end_date,
        uninstallation_date = EXCLUDED.uninstallation_date,
        event_location = EXCLUDED.event_location,
        project_amount = EXCLUDED.project_amount,
        paid_amount = EXCLUDED.paid_amount,
        project_status = EXCLUDED.project_status,
        description = EXCLUDED.description
    RETURNING id INTO v_project_id;

    UPDATE public.crm_deals SET stage = 'WON' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity (deal_id, action, from_status, to_status, note, actor_id)
    VALUES (p_deal_id, 'PROJECT_CREATED', v_deal.stage, 'WON', p_notes, auth.uid());
    RETURN v_project_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_project_from_won_deal(UUID, DATE, DATE, DATE, DATE, TEXT, NUMERIC, NUMERIC, TEXT, TEXT) TO authenticated;

CREATE TABLE IF NOT EXISTS public.reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    due_date TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed')),
    recurrence_type TEXT NOT NULL DEFAULT 'NONE' CHECK (recurrence_type IN ('NONE', 'DAILY', 'WEEKLY', 'MONTHLY', 'CUSTOM')),
    recurrence_interval INTEGER NOT NULL DEFAULT 1 CHECK (recurrence_interval BETWEEN 1 AND 365),
    last_notified_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.reminders
    ADD COLUMN IF NOT EXISTS recurrence_type TEXT NOT NULL DEFAULT 'NONE',
    ADD COLUMN IF NOT EXISTS recurrence_interval INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS last_notified_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS reminders_user_due_idx ON public.reminders(user_id, due_date);
ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view their reminders" ON public.reminders;
CREATE POLICY "Users can view their reminders" ON public.reminders FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "Users can create their reminders" ON public.reminders;
CREATE POLICY "Users can create their reminders" ON public.reminders FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "Users can update their reminders" ON public.reminders;
CREATE POLICY "Users can update their reminders" ON public.reminders FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "Users can delete their reminders" ON public.reminders;
CREATE POLICY "Users can delete their reminders" ON public.reminders FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.push_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL UNIQUE,
    p256dh TEXT NOT NULL,
    auth_key TEXT NOT NULL,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users manage their push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users manage their push subscriptions" ON public.push_subscriptions
    FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS push_sent_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS notifications_pending_push_idx
    ON public.notifications(created_at) WHERE push_sent_at IS NULL;
