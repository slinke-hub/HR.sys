-- Production-only CRM Release 1A foundation. Derived from the approved workflow-compatible source.
-- Contact tasks are generated only when an authorized CRM transition enters
-- Qualification. Their assignees come from the deal, never from auth.uid().
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

DO $production_preflight$
BEGIN
  IF current_user <> 'postgres' OR current_database() <> 'postgres'
     OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999 THEN
    RAISE EXCEPTION 'Production CRM foundation requires PostgreSQL 17.x in database postgres as role postgres';
  END IF;
  IF to_regclass('public.crm_deals') IS NULL OR to_regclass('public.tasks') IS NULL OR to_regclass('public.profiles') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.crm_deals'::regclass AND attname='assigned_to' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.crm_deals'::regclass AND attname='design_task_id' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass AND attname='archived_at' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass AND attname='visible_to' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass AND attname='assignee_ids' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Verified Production CRM/task prerequisites drifted';
  END IF;
  IF to_regprocedure('public.create_task_secure(jsonb)') IS NULL
     OR to_regprocedure('public.email_profile_name(uuid)') IS NULL
     OR to_regprocedure('public.queue_task_notification(uuid,uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Production task-creation/notification dependency is missing; inspect the current Task Manager catalog';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.crm_deals'::regclass AND attname='assignee_ids' AND NOT attisdropped)
     OR to_regclass('public.crm_generated_tasks') IS NOT NULL
     OR to_regprocedure('public.sync_crm_deal_assignees()') IS NOT NULL
     OR to_regprocedure('public.guard_crm_contact_discussion_task()') IS NOT NULL
     OR to_regprocedure('public.crm_is_own_generated_contact_task(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Production already contains partial CRM Release 1A objects; inspect rather than replay';
  END IF;
  IF md5(pg_get_functiondef('public.create_crm_deal_secure(jsonb)'::regprocedure)) <> '8522c1b50cc6ac171106633361b05898'
     OR md5(pg_get_functiondef('public.update_crm_deal_secure(uuid,jsonb)'::regprocedure)) <> '23178f62195f44ba66fe910401706ce0'
     OR md5(pg_get_functiondef('public.get_crm_deal_secure(uuid)'::regprocedure)) <> '5605dc5198254f497927d7ba09c16918'
     OR md5(pg_get_functiondef('public.can_access_crm(uuid)'::regprocedure)) <> '9bbf7402dfaf581ab81a38ad05452628'
     OR md5(pg_get_functiondef('public.can_view_business_financials(uuid)'::regprocedure)) <> 'c29d57300ba3436d10a1632d661ebf98'
     OR md5(pg_get_functiondef('public.create_task_secure(jsonb)'::regprocedure)) <> '08495319b49a3331edfbb629c99934c4'
     OR md5(pg_get_functiondef('public.email_profile_name(uuid)'::regprocedure)) <> '9a30d09999b1e759a9b9ca5768158817'
     OR md5(pg_get_functiondef('public.queue_task_notification(uuid,uuid,text,text)'::regprocedure)) <> '1cf17344666c71d4ec9acf22280554ef' THEN
    RAISE EXCEPTION 'Production CRM, secure task-creation, or notification dependency fingerprint drifted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc routine
     WHERE routine.oid IN (
       'public.create_crm_deal_secure(jsonb)'::regprocedure,
       'public.update_crm_deal_secure(uuid,jsonb)'::regprocedure,
       'public.get_crm_deal_secure(uuid)'::regprocedure,
       'public.can_access_crm(uuid)'::regprocedure,
       'public.can_view_business_financials(uuid)'::regprocedure,
       'public.create_task_secure(jsonb)'::regprocedure,
       'public.email_profile_name(uuid)'::regprocedure,
       'public.queue_task_notification(uuid,uuid,text,text)'::regprocedure
     ) AND (routine.proowner <> 'postgres'::regrole OR NOT routine.prosecdef
       OR NOT ('search_path=public, pg_temp'=ANY(COALESCE(routine.proconfig,ARRAY[]::text[]))))
  ) THEN
    RAISE EXCEPTION 'Production secure CRM RPC owner, definer mode, or search_path drifted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgname='crm_deals_enforce_workflow_transition' AND tgenabled='O')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgname='protect_lost_crm_deal_edits_trigger' AND tgenabled='O')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass AND tgname='crm_design_task_completion_trigger' AND tgenabled='O')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass AND tgname='crm_design_task_status_update_trigger' AND tgenabled='O') THEN
    RAISE EXCEPTION 'Production Negotiation/Lost/Design workflow trigger baseline drifted';
  END IF;
  IF md5(pg_get_functiondef('public.can_manage_task_attachments(uuid,uuid)'::regprocedure)) <> '05cee3a9820835715f0ed5e4de774070'
     OR md5(pg_get_functiondef('public.can_read_task_attachment_file(text,uuid)'::regprocedure)) <> '3eb91925c2deabb14b39df97367b8492'
     OR md5(pg_get_functiondef((SELECT tgfoid FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgname='protect_lost_crm_deal_edits_trigger'))) <> 'aa0b7b5e051c42ee6a04ca49776dbcfe'
     OR md5(pg_get_functiondef((SELECT tgfoid FROM pg_trigger WHERE tgrelid='public.tasks'::regclass AND tgname='crm_design_task_completion_trigger'))) <> '4f456adceb022e91852b41c6f7cec2ea'
     OR md5(pg_get_functiondef((SELECT tgfoid FROM pg_trigger WHERE tgrelid='public.tasks'::regclass AND tgname='crm_design_task_status_update_trigger'))) <> 'd04129cd545a6410257e28de9fe2c1de' THEN
    RAISE EXCEPTION 'Production attachment, Lost-deal, or Design function fingerprint drifted';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint constraint_row
     WHERE constraint_row.conrelid='public.tasks'::regclass
       AND constraint_row.conname='tasks_crm_workflow_kind_check'
       AND pg_get_constraintdef(constraint_row.oid) ILIKE '%QUOTE_PROPOSAL_DESIGN%'
       AND pg_get_constraintdef(constraint_row.oid) ILIKE '%CONTACT_DISCUSSION%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint constraint_row
     WHERE constraint_row.conrelid='public.crm_deals'::regclass
       AND constraint_row.contype='c'
       AND pg_get_constraintdef(constraint_row.oid) ILIKE '%NEGOTIATION%'
  ) THEN
    RAISE EXCEPTION 'Production task workflow kind or Negotiation stage constraint does not support this release';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'mq20_%') <> 12
     OR EXISTS (
       SELECT 1 FROM (VALUES
         ('task_comments','mq20_no_task_comments_delete','DELETE','e0c5f7bdff96fa1477c3e0e38e596c1c'),
         ('task_comments','mq20_no_task_comments_insert','INSERT','49e6dd8168f7a15e2173fc1d11ba52d4'),
         ('task_comments','mq20_no_task_comments_update','UPDATE','a0c3496abd09d8fd5eaed346d91f80e0'),
         ('task_comments','mq20_only_ines_task_comments_select','SELECT','55626ddd4795af2cd5fbc4d3cd80f764'),
         ('task_lists','mq20_no_task_lists_delete','DELETE','e0c5f7bdff96fa1477c3e0e38e596c1c'),
         ('task_lists','mq20_no_task_lists_insert','INSERT','49e6dd8168f7a15e2173fc1d11ba52d4'),
         ('task_lists','mq20_no_task_lists_update','UPDATE','a0c3496abd09d8fd5eaed346d91f80e0'),
         ('task_lists','mq20_only_ines_task_lists_select','SELECT','7a7a4d4f564758b6214f017faed7bfde'),
         ('tasks','mq20_no_tasks_delete','DELETE','e0c5f7bdff96fa1477c3e0e38e596c1c'),
         ('tasks','mq20_no_tasks_insert','INSERT','49e6dd8168f7a15e2173fc1d11ba52d4'),
         ('tasks','mq20_no_tasks_update','UPDATE','a0c3496abd09d8fd5eaed346d91f80e0'),
         ('tasks','mq20_only_ines_tasks_select','SELECT','4fabb76daca5d65ca54656782bb8286e')
       ) expected(tablename,policyname,cmd,expression_md5)
       LEFT JOIN pg_policies actual ON actual.schemaname='public' AND actual.tablename=expected.tablename
         AND actual.policyname=expected.policyname AND actual.cmd=expected.cmd
         AND actual.permissive='RESTRICTIVE' AND actual.roles=ARRAY['authenticated']::name[]
       WHERE actual.policyname IS NULL
          OR md5(COALESCE(actual.qual,'') || '|' || COALESCE(actual.with_check,'')) <> expected.expression_md5
     ) THEN
    RAISE EXCEPTION 'Production 12-policy MQ-20 baseline drifted before CRM migration';
  END IF;
END;
$production_preflight$;

ALTER TABLE public.crm_deals
    ADD COLUMN IF NOT EXISTS assignee_ids uuid[] NOT NULL DEFAULT '{}'::uuid[];

-- Preserve the existing single-assignee contract as the primary assignee.
UPDATE public.crm_deals
   SET assignee_ids = ARRAY[assigned_to]::uuid[]
 WHERE assigned_to IS NOT NULL
   -- Existing Production protection rejects any field change while a deal
   -- remains LOST. Preserve those historical rows as-is; Qualification
   -- automation can safely read their legacy assigned_to value after reopening.
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
BEFORE INSERT OR UPDATE OF assigned_to, assignee_ids ON public.crm_deals
FOR EACH ROW EXECUTE FUNCTION public.sync_crm_deal_assignees();

-- Production does not yet have the generated-task registry. Create an empty,
-- restricted registry for newly generated tasks. Do not invent mappings for
-- legacy Design tasks; their established approval workflow remains unchanged.
CREATE TABLE IF NOT EXISTS public.crm_generated_tasks (
    deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN')),
    task_id uuid NOT NULL UNIQUE REFERENCES public.tasks(id)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (deal_id, kind)
);
ALTER TABLE public.crm_generated_tasks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.crm_generated_tasks FROM PUBLIC, anon, authenticated;

-- Caller-scoped reader used by the Production MQ-20 task/comment/attachment
-- restrictive policies. It never trusts a caller-supplied different user ID.
CREATE OR REPLACE FUNCTION public.crm_is_own_generated_contact_task(p_task_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  SELECT p_task_id IS NOT NULL
     AND p_user_id IS NOT NULL
     AND auth.uid() IS NOT NULL
     AND p_user_id = auth.uid()
     AND EXISTS (
       SELECT 1
         FROM public.tasks task
         JOIN public.crm_deals deal ON deal.id = task.crm_deal_id
         JOIN public.crm_generated_tasks mapping
           ON mapping.deal_id = deal.id
          AND mapping.task_id = task.id
          AND mapping.kind = 'CONTACT_DISCUSSION'
         JOIN public.profiles profile ON profile.id = p_user_id
        WHERE task.id = p_task_id
          AND task.crm_workflow_kind = 'CONTACT_DISCUSSION'
          AND task.archived_at IS NULL
          AND UPPER(COALESCE(deal.stage,'')) <> 'LOST'
          AND profile.is_active IS DISTINCT FROM false
          AND p_user_id = ANY(COALESCE(
                NULLIF(deal.assignee_ids, '{}'::uuid[]),
                CASE WHEN deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[deal.assigned_to]::uuid[] END))
          AND COALESCE(NULLIF(task.assignee_ids, '{}'::uuid[]),
                CASE WHEN task.assignee_id IS NULL THEN '{}'::uuid[] ELSE ARRAY[task.assignee_id]::uuid[] END)
              = COALESCE(NULLIF(deal.assignee_ids, '{}'::uuid[]),
                CASE WHEN deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[deal.assigned_to]::uuid[] END)
          AND task.assignee_id = (COALESCE(NULLIF(deal.assignee_ids, '{}'::uuid[]),
                CASE WHEN deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[deal.assigned_to]::uuid[] END))[1]
          AND task.visible_to = COALESCE(NULLIF(deal.assignee_ids, '{}'::uuid[]),
                CASE WHEN deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[deal.assigned_to]::uuid[] END)
     );
$function$;
ALTER FUNCTION public.crm_is_own_generated_contact_task(uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.crm_is_own_generated_contact_task(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_is_own_generated_contact_task(uuid,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_crm_contact_discussion_task(p_deal_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_assignees uuid[];
    v_existing_id uuid;
    v_existing_count integer;
    v_task jsonb;
    v_task_id uuid;
    v_previous_context text := current_setting('app.crm_contact_discussion_creation', true);
    v_kind constant text := 'CONTACT_DISCUSSION';
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
    IF UPPER(COALESCE(v_deal.stage, '')) <> 'QUALIFICATION' THEN
        RAISE EXCEPTION 'Contact Discussion tasks require a Qualification deal' USING ERRCODE = '23514';
    END IF;
    v_assignees := COALESCE(
        NULLIF(v_deal.assignee_ids, '{}'::uuid[]),
        CASE WHEN v_deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[v_deal.assigned_to]::uuid[] END
    );
    IF cardinality(v_assignees) = 0 THEN
        RAISE EXCEPTION 'Assign an active deal owner before moving this deal to Qualification' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(v_assignees) AS selected(id)
         WHERE NOT EXISTS (
             SELECT 1 FROM public.profiles profile
              WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false
         )
    ) THEN
        RAISE EXCEPTION 'Every deal assignee must be active before entering Qualification' USING ERRCODE = '23514';
    END IF;

    SELECT task_id INTO v_task_id FROM public.crm_generated_tasks
     WHERE deal_id = p_deal_id AND kind = v_kind;
    IF FOUND THEN
        IF v_task_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.tasks task
             WHERE task.id = v_task_id
               AND task.crm_deal_id = p_deal_id
               AND task.crm_workflow_kind = v_kind
               AND COALESCE(NULLIF(task.assignee_ids, '{}'::uuid[]),
                   CASE WHEN task.assignee_id IS NULL THEN '{}'::uuid[] ELSE ARRAY[task.assignee_id]::uuid[] END)
                   = v_assignees
        ) THEN
            RAISE EXCEPTION 'The registered Contact Discussion task does not match the current deal assignees; review required' USING ERRCODE = '23514';
        END IF;
        RETURN v_task_id;
    END IF;

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
               AND COALESCE(NULLIF(task.assignee_ids, '{}'::uuid[]),
                   CASE WHEN task.assignee_id IS NULL THEN '{}'::uuid[] ELSE ARRAY[task.assignee_id]::uuid[] END)
                   = v_assignees
        ) THEN
            RAISE EXCEPTION 'Existing Contact Discussion task assignees differ from the current deal assignees; review required' USING ERRCODE = '23514';
        END IF;
        INSERT INTO public.crm_generated_tasks(deal_id, kind, task_id)
        VALUES (p_deal_id, v_kind, v_existing_id)
        ON CONFLICT (deal_id, kind) DO NOTHING;
        SELECT task_id INTO v_task_id FROM public.crm_generated_tasks
         WHERE deal_id = p_deal_id AND kind = v_kind;
        IF NOT EXISTS (
            SELECT 1 FROM public.tasks task
             WHERE task.id = v_task_id
               AND task.crm_deal_id = p_deal_id
               AND task.crm_workflow_kind = v_kind
               AND COALESCE(NULLIF(task.assignee_ids, '{}'::uuid[]),
                   CASE WHEN task.assignee_id IS NULL THEN '{}'::uuid[] ELSE ARRAY[task.assignee_id]::uuid[] END)
                   = v_assignees
        ) THEN
            RAISE EXCEPTION 'The registered Contact Discussion task does not match the current deal assignees; review required' USING ERRCODE = '23514';
        END IF;
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
        'assignee_id', v_assignees[1],
        'assignee_ids', to_jsonb(v_assignees),
        'created_by', auth.uid(),
        'status', 'todo',
        'priority', 'medium',
        'category', 'CRM',
        'visibility', 'private',
        'visible_to', to_jsonb(v_assignees),
        'notify_via_email', false,
        'crm_deal_id', p_deal_id,
        'crm_workflow_kind', 'CONTACT_DISCUSSION'
    ));
    PERFORM set_config('app.crm_contact_discussion_creation', COALESCE(v_previous_context, ''), true);
    v_task_id := NULLIF(v_task->>'id', '')::uuid;
    IF v_task_id IS NULL THEN
        RAISE EXCEPTION 'Contact Discussion task creation returned no task ID' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.crm_generated_tasks
         WHERE deal_id = p_deal_id AND kind = v_kind AND task_id = v_task_id
    ) THEN
        RAISE EXCEPTION 'Contact Discussion task registration did not complete' USING ERRCODE = '23514';
    END IF;
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
    v_assignees uuid[];
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (OLD.crm_workflow_kind = 'CONTACT_DISCUSSION'
            OR NEW.crm_workflow_kind = 'CONTACT_DISCUSSION')
           AND (NEW.crm_workflow_kind IS DISTINCT FROM OLD.crm_workflow_kind
                OR NEW.crm_deal_id IS DISTINCT FROM OLD.crm_deal_id) THEN
            RAISE EXCEPTION 'CRM Contact Discussion task identity is protected' USING ERRCODE = '42501';
        END IF;
        -- Preserve ordinary Task Manager updates. The legacy identity guard
        -- still rejects identity changes and retired approval statuses.
        RETURN NEW;
    END IF;
    IF NEW.crm_workflow_kind IS DISTINCT FROM 'CONTACT_DISCUSSION' THEN RETURN NEW; END IF;
    IF current_setting('app.crm_contact_discussion_creation', true) IS DISTINCT FROM 'on'
       OR NEW.crm_deal_id IS NULL THEN
        RAISE EXCEPTION 'Contact Discussion tasks can only be created by the CRM Qualification workflow' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = NEW.crm_deal_id FOR UPDATE;
    IF FOUND THEN
        v_assignees := COALESCE(
            NULLIF(v_deal.assignee_ids, '{}'::uuid[]),
            CASE WHEN v_deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[v_deal.assigned_to]::uuid[] END
        );
    END IF;
    IF NOT FOUND OR UPPER(COALESCE(v_deal.stage, '')) <> 'QUALIFICATION'
       OR COALESCE(cardinality(v_assignees), 0) = 0
       OR COALESCE(NEW.assignee_ids, '{}'::uuid[]) IS DISTINCT FROM v_assignees
       OR NEW.assignee_id IS DISTINCT FROM v_assignees[1] THEN
        RAISE EXCEPTION 'Contact Discussion task recipients must match the current active deal assignees' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(v_assignees) AS selected(id)
         WHERE NOT EXISTS (
             SELECT 1 FROM public.profiles profile
              WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false
         )
    ) THEN
        RAISE EXCEPTION 'Contact Discussion recipients must be active employees' USING ERRCODE = '23514';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF auth.uid() IS NULL
           OR NOT COALESCE(public.can_access_crm(auth.uid()), false)
           OR NOT EXISTS (
               SELECT 1 FROM public.profiles profile
                WHERE profile.id = auth.uid() AND profile.is_active IS DISTINCT FROM false
           ) THEN
            RAISE EXCEPTION 'CRM access denied for generated Contact Discussion task' USING ERRCODE = '42501';
        END IF;
        -- This Production-specific guard is the Contact Discussion identity
        -- authority. It registers only Contact tasks created through this
        -- transaction context. Existing Design tasks remain outside this
        -- registry path and retain their existing identity/approval flow.
        INSERT INTO public.crm_generated_tasks(deal_id, kind, task_id)
        VALUES (NEW.crm_deal_id, 'CONTACT_DISCUSSION', NEW.id)
        ON CONFLICT (deal_id, kind) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM public.crm_generated_tasks mapping
             WHERE mapping.deal_id = NEW.crm_deal_id
               AND mapping.kind = 'CONTACT_DISCUSSION'
               AND mapping.task_id = NEW.id
        ) THEN
            RAISE EXCEPTION 'Contact Discussion task identity is already registered to another task' USING ERRCODE = '23505';
        END IF;
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

REVOKE ALL ON FUNCTION public.sync_crm_deal_assignees() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_crm_contact_discussion_task(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.guard_crm_contact_discussion_task() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_crm_contact_discussion_on_qualification() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
