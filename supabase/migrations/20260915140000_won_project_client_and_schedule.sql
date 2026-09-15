BEGIN;

-- Preserve existing time-only values by combining them with the project's event date,
-- then allow the Won-order workflow to store the full local installation schedule.
ALTER TABLE public.projects
    ALTER COLUMN installation_time TYPE timestamp without time zone
    USING CASE
        WHEN installation_time IS NULL THEN NULL
        ELSE COALESCE(event_date, CURRENT_DATE) + installation_time
    END,
    ALTER COLUMN uninstallation_time TYPE timestamp without time zone
    USING CASE
        WHEN uninstallation_time IS NULL THEN NULL
        ELSE COALESCE(event_date, CURRENT_DATE) + uninstallation_time
    END;

COMMENT ON COLUMN public.projects.installation_time IS 'Local installation date and time captured when a deal is moved to Won.';
COMMENT ON COLUMN public.projects.uninstallation_time IS 'Local uninstallation date and time captured when a deal is moved to Won.';

CREATE OR REPLACE FUNCTION public.create_project_from_won_deal_v2(p_deal_id uuid, p_order jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_project_id uuid;
    v_assigned uuid[];
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deal not found'; END IF;
    IF v_deal.workflow_status <> 'APPROVED' THEN RAISE EXCEPTION 'Complete the deal workflow before opening the project'; END IF;
    IF auth.uid() NOT IN (COALESCE(v_deal.created_by, auth.uid()), COALESCE(v_deal.assigned_to, auth.uid()))
       AND NOT public.is_crm_approval_admin(auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND UPPER(COALESCE(p.role, '')) = 'MANAGER') THEN
        RAISE EXCEPTION 'Only the deal team or management can open this project';
    END IF;
    SELECT COALESCE(array_agg(value::uuid), '{}') INTO v_assigned
    FROM jsonb_array_elements_text(COALESCE(p_order->'assigned_people', '[]'::jsonb)) value;
    IF NULLIF(BTRIM(COALESCE(p_order->>'event_date', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->>'event_start_time', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->'client'->>'name', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->>'installation_type', '')), '') IS NULL THEN
        RAISE EXCEPTION 'Event date, starting time, client name, and installation type are required';
    END IF;
    IF COALESCE(array_length(v_assigned, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one employee';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(v_assigned) assignee_id
        LEFT JOIN public.profiles profile ON profile.id = assignee_id
        WHERE profile.id IS NULL OR profile.is_active IS FALSE
    ) THEN
        RAISE EXCEPTION 'Projects can only be assigned to active employees';
    END IF;
    IF jsonb_typeof(COALESCE(p_order->'equipment', '[]'::jsonb)) <> 'array'
       OR jsonb_array_length(COALESCE(p_order->'equipment', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Add at least one equipment item';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(p_order->'equipment', '[]'::jsonb)) equipment_item
        WHERE NULLIF(BTRIM(COALESCE(equipment_item->>'item', '')), '') IS NULL
           OR NULLIF(BTRIM(COALESCE(equipment_item->>'quantity', '')), '') IS NULL
    ) THEN
        RAISE EXCEPTION 'Every equipment item needs an item name and quantity';
    END IF;

    SELECT id INTO v_project_id FROM public.projects WHERE deal_id = p_deal_id ORDER BY created_at LIMIT 1 FOR UPDATE;
    IF v_project_id IS NULL THEN
        INSERT INTO public.projects(
            project_name, project_type, description, assigned_people, project_tags,
            deal_id, client_id, event_date, start_date, event_location, project_amount,
            paid_amount, project_status, source, order_employee_id, event_start_time,
            installation_time, uninstallation_time, client_snapshot, event_location_text,
            installation_type, equipment
        ) VALUES (
            v_deal.title, 'Client', NULLIF(p_order->>'notes', ''), v_assigned, ARRAY['Won Deal']::text[],
            v_deal.id, v_deal.client_id, (p_order->>'event_date')::date, (p_order->>'event_date')::date,
            NULLIF(p_order->>'location_url', ''), COALESCE(NULLIF(p_order->>'project_amount', '')::numeric, v_deal.amount, 0),
            COALESCE(NULLIF(p_order->>'paid_amount', '')::numeric, 0), 'Not Confirmed', 'WON_DEAL',
            auth.uid(), (p_order->>'event_start_time')::time,
            NULLIF(p_order->>'installation_time', '')::timestamp, NULLIF(p_order->>'uninstallation_time', '')::timestamp,
            p_order->'client', NULLIF(p_order->>'location_text', ''),
            p_order->>'installation_type', p_order->'equipment'
        ) RETURNING id INTO v_project_id;
    ELSE
        UPDATE public.projects SET
            description = NULLIF(p_order->>'notes', ''), assigned_people = v_assigned,
            event_date = (p_order->>'event_date')::date, start_date = (p_order->>'event_date')::date,
            event_location = NULLIF(p_order->>'location_url', ''),
            project_amount = COALESCE(NULLIF(p_order->>'project_amount', '')::numeric, v_deal.amount, 0),
            paid_amount = COALESCE(NULLIF(p_order->>'paid_amount', '')::numeric, 0),
            order_employee_id = auth.uid(),
            event_start_time = (p_order->>'event_start_time')::time,
            installation_time = NULLIF(p_order->>'installation_time', '')::timestamp,
            uninstallation_time = NULLIF(p_order->>'uninstallation_time', '')::timestamp,
            client_snapshot = p_order->'client', event_location_text = NULLIF(p_order->>'location_text', ''),
            installation_type = p_order->>'installation_type', equipment = p_order->'equipment'
        WHERE id = v_project_id;
    END IF;
    UPDATE public.crm_deals SET stage = 'WON' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (p_deal_id, 'PROJECT_CREATED', v_deal.stage, 'WON', NULLIF(p_order->>'notes', ''), auth.uid());
    RETURN v_project_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_project_from_won_deal_v2(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_project_from_won_deal_v2(uuid, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
