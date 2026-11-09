-- CRM Release 1A: workflow-compatible Contact Discussion automation.
-- Contact tasks are generated only when an authorized CRM transition enters
-- Qualification. Their assignees come from the deal, never from auth.uid().
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.crm_deals
    ADD COLUMN IF NOT EXISTS assignee_ids uuid[] NOT NULL DEFAULT '{}'::uuid[];

-- Preserve the existing single-assignee contract as the primary assignee.
UPDATE public.crm_deals
   SET assignee_ids = ARRAY[assigned_to]::uuid[]
 WHERE assigned_to IS NOT NULL
   -- Existing Production protection rejects any field change while a deal
   -- remains LOST. Preserve those historical rows as-is; the assignee-sync
   -- trigger will populate the array only after an authorized reopen.
   AND UPPER(COALESCE(stage, '')) <> 'LOST'
   AND COALESCE(cardinality(assignee_ids), 0) = 0;

-- Keep the established RPC security checks, financial redaction and single
-- assigned_to compatibility field while accepting the existing task-style
-- UUID array for multi-assignee deals.
CREATE OR REPLACE FUNCTION public.create_crm_deal_secure(p_deal jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_client_id uuid;
  v_assignees uuid[];
  v_assigned_to uuid;
  v_title text := NULLIF(BTRIM(COALESCE(p_deal->>'title', '')), '');
  v_first_contact date := NULLIF(BTRIM(COALESCE(p_deal->>'first_contact_date', '')), '')::date;
  v_contact_method text := NULLIF(BTRIM(COALESCE(p_deal->>'contact_method', '')), '');
  v_amount numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  IF v_title IS NULL THEN RAISE EXCEPTION 'Deal title is required' USING ERRCODE = '22023'; END IF;
  IF v_first_contact IS NULL THEN RAISE EXCEPTION 'First contact date is required' USING ERRCODE = '23514'; END IF;
  IF v_contact_method IS NULL THEN RAISE EXCEPTION 'Contact method is required' USING ERRCODE = '23514'; END IF;
  IF NULLIF(BTRIM(COALESCE(p_deal->>'client_id', '')), '') IS NULL THEN
    RAISE EXCEPTION 'Client is required' USING ERRCODE = '23514';
  END IF;
  v_client_id := (p_deal->>'client_id')::uuid;
  IF NOT EXISTS (SELECT 1 FROM public.crm_clients WHERE id = v_client_id) THEN
    RAISE EXCEPTION 'CRM client not found' USING ERRCODE = 'P0002';
  END IF;

  IF jsonb_typeof(p_deal->'assignee_ids') = 'array' THEN
    SELECT COALESCE(array_agg(items.id ORDER BY items.first_seen), '{}'::uuid[])
      INTO v_assignees
      FROM (
        SELECT value::uuid AS id, min(ordinality) AS first_seen
          FROM jsonb_array_elements_text(p_deal->'assignee_ids') WITH ORDINALITY AS input(value, ordinality)
         GROUP BY value::uuid
      ) items;
    v_assigned_to := v_assignees[1];
    IF NULLIF(BTRIM(COALESCE(p_deal->>'assigned_to', '')), '') IS NOT NULL
       AND (p_deal->>'assigned_to')::uuid IS DISTINCT FROM v_assigned_to THEN
      RAISE EXCEPTION 'assigned_to must be the first selected deal assignee' USING ERRCODE = '23514';
    END IF;
  ELSE
    v_assigned_to := NULLIF(BTRIM(COALESCE(p_deal->>'assigned_to', '')), '')::uuid;
    v_assignees := CASE WHEN v_assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[v_assigned_to]::uuid[] END;
  END IF;
  IF cardinality(v_assignees) = 0 OR EXISTS (
      SELECT 1 FROM unnest(v_assignees) AS selected(id)
       WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false)
  ) THEN
    RAISE EXCEPTION 'Deal assignees must include at least one active employee' USING ERRCODE = '23514';
  END IF;

  IF public.can_view_business_financials(auth.uid())
     AND NULLIF(BTRIM(COALESCE(p_deal->>'amount', '')), '') IS NOT NULL THEN
    v_amount := (p_deal->>'amount')::numeric;
  END IF;
  INSERT INTO public.crm_deals(
    client_id, title, amount, stage, closing_date, assigned_to, assignee_ids, event_type,
    first_contact_date, contact_method, lead_source, technical_description, created_by
  ) VALUES (
    v_client_id, v_title, v_amount, 'LEAD', NULLIF(p_deal->>'closing_date', '')::date,
    v_assigned_to, v_assignees, NULLIF(p_deal->>'event_type', ''), v_first_contact, v_contact_method,
    NULLIF(p_deal->>'lead_source', ''), NULLIF(p_deal->>'technical_description', ''), auth.uid()
  ) RETURNING id INTO v_id;
  INSERT INTO public.crm_deal_activity(deal_id, action, to_status, actor_id)
  VALUES (v_id, 'DEAL_CREATED', 'LEAD', auth.uid());
  RETURN public.get_crm_deal_secure(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_crm_deal_secure(p_deal_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deal public.crm_deals%ROWTYPE;
  v_client_id uuid;
  v_assignees uuid[];
  v_assigned_to uuid;
  v_amount numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
  IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN
    RAISE EXCEPTION 'Lost deals are read-only until moved to another stage' USING ERRCODE = '42501';
  END IF;
  IF p_patch ? 'client_id' THEN
    v_client_id := NULLIF(BTRIM(COALESCE(p_patch->>'client_id', '')), '')::uuid;
    IF v_client_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.crm_clients WHERE id = v_client_id) THEN
      RAISE EXCEPTION 'CRM client not found' USING ERRCODE = 'P0002';
    END IF;
  ELSE v_client_id := v_deal.client_id;
  END IF;

  IF p_patch ? 'assignee_ids' THEN
    IF jsonb_typeof(p_patch->'assignee_ids') <> 'array' THEN
      RAISE EXCEPTION 'assignee_ids must be an array' USING ERRCODE = '22023';
    END IF;
    SELECT COALESCE(array_agg(items.id ORDER BY items.first_seen), '{}'::uuid[])
      INTO v_assignees
      FROM (
        SELECT value::uuid AS id, min(ordinality) AS first_seen
          FROM jsonb_array_elements_text(p_patch->'assignee_ids') WITH ORDINALITY AS input(value, ordinality)
         GROUP BY value::uuid
      ) items;
    v_assigned_to := v_assignees[1];
    IF p_patch ? 'assigned_to'
       AND NULLIF(BTRIM(COALESCE(p_patch->>'assigned_to', '')), '')::uuid IS DISTINCT FROM v_assigned_to THEN
      RAISE EXCEPTION 'assigned_to must be the first selected deal assignee' USING ERRCODE = '23514';
    END IF;
  ELSIF p_patch ? 'assigned_to' THEN
    v_assigned_to := NULLIF(BTRIM(COALESCE(p_patch->>'assigned_to', '')), '')::uuid;
    IF v_assigned_to IS NULL THEN
      RAISE EXCEPTION 'Deal assignee must be an active employee' USING ERRCODE = '23514';
    END IF;
    v_assignees := ARRAY[v_assigned_to]::uuid[];
  ELSE
    v_assigned_to := v_deal.assigned_to;
    v_assignees := COALESCE(v_deal.assignee_ids, '{}'::uuid[]);
  END IF;
  IF EXISTS (
      SELECT 1 FROM unnest(v_assignees) AS selected(id)
       WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false)
  ) THEN
    RAISE EXCEPTION 'Every deal assignee must be an active employee' USING ERRCODE = '23514';
  END IF;
  IF public.can_view_business_financials(auth.uid()) AND p_patch ? 'amount' THEN
    v_amount := NULLIF(BTRIM(COALESCE(p_patch->>'amount', '')), '')::numeric;
  ELSE v_amount := v_deal.amount;
  END IF;
  UPDATE public.crm_deals SET
    title = COALESCE(NULLIF(BTRIM(COALESCE(p_patch->>'title', '')), ''), title),
    client_id = v_client_id,
    amount = COALESCE(v_amount, 0),
    closing_date = CASE WHEN p_patch ? 'closing_date' THEN NULLIF(p_patch->>'closing_date', '')::date ELSE closing_date END,
    assigned_to = v_assigned_to,
    assignee_ids = v_assignees,
    event_type = CASE WHEN p_patch ? 'event_type' THEN NULLIF(p_patch->>'event_type', '') ELSE event_type END,
    first_contact_date = CASE WHEN p_patch ? 'first_contact_date' THEN NULLIF(p_patch->>'first_contact_date', '')::date ELSE first_contact_date END,
    contact_method = CASE WHEN p_patch ? 'contact_method' THEN NULLIF(BTRIM(COALESCE(p_patch->>'contact_method', '')), '') ELSE contact_method END,
    lead_source = CASE WHEN p_patch ? 'lead_source' THEN NULLIF(p_patch->>'lead_source', '') ELSE lead_source END,
    technical_description = CASE WHEN p_patch ? 'technical_description' THEN NULLIF(p_patch->>'technical_description', '') ELSE technical_description END
  WHERE id = p_deal_id;
  INSERT INTO public.crm_deal_activity(deal_id, action, actor_id, note)
  VALUES (p_deal_id, CASE WHEN v_deal.assignee_ids IS DISTINCT FROM v_assignees THEN 'DEAL_REASSIGNED' ELSE 'DEAL_UPDATED' END,
          auth.uid(), NULLIF((p_patch - 'amount')::text, '{}'));
  RETURN public.get_crm_deal_secure(p_deal_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_crm_deal_assignees()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_assignees uuid[];
    v_unique_count integer;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_assignees := COALESCE(NEW.assignee_ids, '{}'::uuid[]);
        IF cardinality(v_assignees) = 0 AND NEW.assigned_to IS NOT NULL THEN
            v_assignees := ARRAY[NEW.assigned_to]::uuid[];
        ELSIF cardinality(v_assignees) > 0 THEN
            NEW.assigned_to := v_assignees[1];
        END IF;
    ELSIF NEW.assignee_ids IS DISTINCT FROM OLD.assignee_ids THEN
        v_assignees := COALESCE(NEW.assignee_ids, '{}'::uuid[]);
        NEW.assigned_to := v_assignees[1];
    ELSIF NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
        v_assignees := CASE WHEN NEW.assigned_to IS NULL
                            THEN '{}'::uuid[] ELSE ARRAY[NEW.assigned_to]::uuid[] END;
    ELSE
        v_assignees := COALESCE(NEW.assignee_ids, '{}'::uuid[]);
        -- Legacy Lost rows intentionally skip the migration backfill. On an
        -- authorized reopen, preserve their existing single owner while
        -- synchronizing the new array representation.
        IF cardinality(v_assignees) = 0 AND NEW.assigned_to IS NOT NULL THEN
            v_assignees := ARRAY[NEW.assigned_to]::uuid[];
        END IF;
        NEW.assigned_to := v_assignees[1];
    END IF;

    SELECT count(DISTINCT selected.id) INTO v_unique_count FROM unnest(v_assignees) AS selected(id);
    IF cardinality(v_assignees) <> v_unique_count THEN
        RAISE EXCEPTION 'Deal assignees must be unique' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(v_assignees) AS selected(id)
         WHERE selected.id IS NULL
            OR NOT EXISTS (
                SELECT 1 FROM public.profiles profile
                 WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false
            )
    ) THEN
        RAISE EXCEPTION 'Every deal assignee must be an active employee' USING ERRCODE = '23514';
    END IF;
    NEW.assignee_ids := v_assignees;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_deal_assignees_sync ON public.crm_deals;
CREATE TRIGGER crm_deal_assignees_sync
BEFORE INSERT OR UPDATE OF assigned_to, assignee_ids, stage ON public.crm_deals
FOR EACH ROW EXECUTE FUNCTION public.sync_crm_deal_assignees();

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_crm_workflow_kind_check;
ALTER TABLE public.tasks ADD CONSTRAINT tasks_crm_workflow_kind_check
    CHECK (crm_workflow_kind IS NULL OR crm_workflow_kind IN ('QUOTE_PROPOSAL_DESIGN', 'CONTACT_DISCUSSION'));

CREATE TABLE IF NOT EXISTS public.crm_generated_tasks (
    deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    event_key text NOT NULL,
    task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (deal_id, event_key)
);
ALTER TABLE public.crm_generated_tasks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.crm_generated_tasks FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_crm_contact_discussion_task(p_deal_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_existing_id uuid;
    v_existing_count integer;
    v_task jsonb;
    v_task_id uuid;
    v_previous_context text := current_setting('app.crm_contact_discussion_creation', true);
    v_event_key constant text := 'qualification-entry-v1';
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
    IF UPPER(COALESCE(v_deal.stage, '')) <> 'QUALIFICATION' THEN
        RAISE EXCEPTION 'Contact Discussion tasks require a Qualification deal' USING ERRCODE = '23514';
    END IF;
    IF COALESCE(cardinality(v_deal.assignee_ids), 0) = 0 THEN
        RAISE EXCEPTION 'Assign an active deal owner before moving this deal to Qualification' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(v_deal.assignee_ids) AS selected(id)
         WHERE NOT EXISTS (
             SELECT 1 FROM public.profiles profile
              WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false
         )
    ) THEN
        RAISE EXCEPTION 'Every deal assignee must be active before entering Qualification' USING ERRCODE = '23514';
    END IF;

    SELECT task_id INTO v_task_id FROM public.crm_generated_tasks
     WHERE deal_id = p_deal_id AND event_key = v_event_key;
    IF FOUND THEN RETURN v_task_id; END IF;

    SELECT count(*) INTO v_existing_count
      FROM public.tasks task
     WHERE task.crm_deal_id = p_deal_id
       AND task.crm_workflow_kind = 'CONTACT_DISCUSSION';
    IF v_existing_count > 1 THEN
        RAISE EXCEPTION 'Multiple Contact Discussion tasks are already linked to this deal; review required' USING ERRCODE = '23514';
    ELSIF v_existing_count = 1 THEN
        SELECT task.id INTO v_existing_id FROM public.tasks task
         WHERE task.crm_deal_id = p_deal_id
           AND task.crm_workflow_kind = 'CONTACT_DISCUSSION'
         ORDER BY task.id LIMIT 1;
        IF NOT EXISTS (
            SELECT 1 FROM public.tasks task
             WHERE task.id = v_existing_id
               AND COALESCE(task.assignee_ids, '{}'::uuid[]) = v_deal.assignee_ids
        ) THEN
            RAISE EXCEPTION 'Existing Contact Discussion task assignees differ from the current deal assignees; review required' USING ERRCODE = '23514';
        END IF;
        INSERT INTO public.crm_generated_tasks(deal_id, event_key, task_id)
        VALUES (p_deal_id, v_event_key, v_existing_id)
        ON CONFLICT (deal_id, event_key) DO NOTHING;
        SELECT task_id INTO v_task_id FROM public.crm_generated_tasks
         WHERE deal_id = p_deal_id AND event_key = v_event_key;
        RETURN v_task_id;
    END IF;

    PERFORM set_config('app.crm_contact_discussion_creation', 'on', true);
    v_task := public.create_task_secure(jsonb_build_object(
        'title', 'Contact Discussion: ' || v_deal.title,
        'title_i18n', jsonb_build_object(
            'en', 'Contact Discussion: ' || v_deal.title,
            'ar', 'مناقشة التواصل: ' || v_deal.title
        ),
        'description', 'Follow up on the CRM deal contact discussion.',
        'description_i18n', jsonb_build_object(
            'en', 'Follow up on the CRM deal contact discussion.',
            'ar', 'متابعة مناقشة التواصل الخاصة بصفقة إدارة علاقات العملاء.'
        ),
        'assignee_id', v_deal.assignee_ids[1],
        'assignee_ids', to_jsonb(v_deal.assignee_ids),
        'created_by', auth.uid(),
        'status', 'todo',
        'priority', 'medium',
        'category', 'CRM',
        'visibility', 'private',
        'visible_to', to_jsonb(v_deal.assignee_ids),
        'notify_via_email', false,
        'crm_deal_id', p_deal_id,
        'crm_workflow_kind', 'CONTACT_DISCUSSION'
    ));
    PERFORM set_config('app.crm_contact_discussion_creation', COALESCE(v_previous_context, ''), true);
    v_task_id := NULLIF(v_task->>'id', '')::uuid;
    IF v_task_id IS NULL THEN
        RAISE EXCEPTION 'Contact Discussion task creation returned no task ID' USING ERRCODE = '23514';
    END IF;
    INSERT INTO public.crm_generated_tasks(deal_id, event_key, task_id)
    VALUES (p_deal_id, v_event_key, v_task_id);
    RETURN v_task_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_crm_contact_discussion_task()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE'
       AND OLD.crm_workflow_kind = 'CONTACT_DISCUSSION'
       AND (NEW.crm_workflow_kind IS DISTINCT FROM OLD.crm_workflow_kind
            OR NEW.crm_deal_id IS DISTINCT FROM OLD.crm_deal_id)
       AND current_setting('app.crm_contact_discussion_creation', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'CRM Contact Discussion task identity is protected' USING ERRCODE = '42501';
    END IF;
    IF NEW.crm_workflow_kind IS DISTINCT FROM 'CONTACT_DISCUSSION' THEN RETURN NEW; END IF;
    IF current_setting('app.crm_contact_discussion_creation', true) IS DISTINCT FROM 'on'
       OR NEW.crm_deal_id IS NULL THEN
        RAISE EXCEPTION 'Contact Discussion tasks can only be created by the CRM Qualification workflow' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = NEW.crm_deal_id FOR UPDATE;
    IF NOT FOUND OR UPPER(COALESCE(v_deal.stage, '')) <> 'QUALIFICATION'
       OR COALESCE(cardinality(v_deal.assignee_ids), 0) = 0
       OR COALESCE(NEW.assignee_ids, '{}'::uuid[]) IS DISTINCT FROM v_deal.assignee_ids
       OR NEW.assignee_id IS DISTINCT FROM v_deal.assignee_ids[1] THEN
        RAISE EXCEPTION 'Contact Discussion task recipients must match the current active deal assignees' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(NEW.assignee_ids) AS selected(id)
         WHERE NOT EXISTS (
             SELECT 1 FROM public.profiles profile
              WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false
         )
    ) THEN
        RAISE EXCEPTION 'Contact Discussion recipients must be active employees' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_contact_discussion_task_guard ON public.tasks;
CREATE TRIGGER crm_contact_discussion_task_guard
BEFORE INSERT OR UPDATE OF crm_deal_id, crm_workflow_kind ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.guard_crm_contact_discussion_task();

CREATE OR REPLACE FUNCTION public.create_crm_contact_discussion_on_qualification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.stage = 'QUALIFICATION' AND OLD.stage IS DISTINCT FROM 'QUALIFICATION' THEN
        PERFORM public.create_crm_contact_discussion_task(NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_contact_discussion_on_qualification ON public.crm_deals;
CREATE TRIGGER crm_contact_discussion_on_qualification
AFTER UPDATE OF stage ON public.crm_deals
FOR EACH ROW EXECUTE FUNCTION public.create_crm_contact_discussion_on_qualification();

REVOKE ALL ON FUNCTION public.sync_crm_deal_assignees() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_crm_contact_discussion_task(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_crm_contact_discussion_task() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_crm_contact_discussion_on_qualification() FROM PUBLIC, anon;

COMMIT;
