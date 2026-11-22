-- Permit authorized CRM administrators to start the Quote & Proposal task
-- without being assigned to the deal. Non-admin CRM users remain assignment-bound.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
BEGIN
  IF to_regprocedure('public.start_crm_quote_proposal(uuid)') IS NULL
     OR to_regprocedure('public.can_access_crm(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CRM Quote & Proposal workflow functions are unavailable';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.start_crm_quote_proposal(p_deal_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $body$
DECLARE
  d public.crm_deals%ROWTYPE;
  task_id uuid;
  already_registered boolean;
  list_id uuid;
  designer_id uuid;
  active_route_count integer;
  caller_is_admin boolean;
BEGIN
  IF auth.uid() IS NULL
     OR NOT COALESCE(public.can_access_crm(auth.uid()), false)
     OR NOT EXISTS (
       SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND is_active IS DISTINCT FROM false
     ) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(role, ''), '[_-]+', ' ', 'g')))
          IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
  ) INTO caller_is_admin;

  SELECT * INTO d FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;

  IF NOT caller_is_admin
     AND auth.uid() IS DISTINCT FROM d.created_by
     AND auth.uid() IS DISTINCT FROM d.assigned_to
     AND NOT auth.uid() = ANY(COALESCE(d.assignee_ids, '{}'::uuid[])) THEN
    RAISE EXCEPTION 'Deal assignment required' USING ERRCODE = '42501';
  END IF;

  IF d.stage <> 'DISCUSSION' THEN
    RAISE EXCEPTION 'Deal must be in Discussion' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.crm_deal_attachments
       WHERE deal_id = p_deal_id AND category = 'QUOTATION' AND is_archived = false
         AND NULLIF(BTRIM(file_url), '') IS NOT NULL
     ) OR NOT EXISTS (
       SELECT 1 FROM public.crm_deal_attachments
       WHERE deal_id = p_deal_id AND category = 'PROPOSAL' AND is_archived = false
         AND NULLIF(BTRIM(file_url), '') IS NOT NULL
         AND NULLIF(BTRIM(description), '') IS NOT NULL
         AND file_type LIKE 'image/%'
     ) THEN
    RAISE EXCEPTION 'Quote and described proposal image are required' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.crm_generated_tasks
    WHERE deal_id = p_deal_id AND kind = 'QUOTE_PROPOSAL_DESIGN'
  ) THEN
    RAISE EXCEPTION 'Historical Design mapping requires review' USING ERRCODE = '23514';
  END IF;

  SELECT count(*) INTO active_route_count
  FROM hrsys_private.crm_quote_proposal_routes WHERE is_active;
  IF active_route_count <> 1 THEN
    RAISE EXCEPTION 'Configure exactly one active Design route' USING ERRCODE = '23514';
  END IF;

  SELECT route.list_id, route.assignee_id INTO list_id, designer_id
  FROM hrsys_private.crm_quote_proposal_routes route WHERE route.is_active;
  IF NOT EXISTS (
    SELECT 1
    FROM public.task_lists list
    JOIN public.profiles designer ON designer.id = designer_id
    JOIN public.departments department ON department.id = list.department_id
    WHERE list.id = list_id AND designer.is_active IS TRUE
      AND designer.department_id = list.department_id AND department.is_active IS TRUE
      AND COALESCE(list.name, '') ~* '(design|تصميم)'
  ) THEN
    RAISE EXCEPTION 'Design list and designer department mismatch' USING ERRCODE = '23514';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.crm_generated_tasks
    WHERE deal_id = p_deal_id AND kind = 'QUOTE_PROPOSAL'
  ) INTO already_registered;
  INSERT INTO hrsys_private.crm_quote_proposal_context(backend_pid, transaction_id, actor_id, deal_id, list_id, designer_id)
  VALUES(pg_backend_pid(), txid_current(), auth.uid(), p_deal_id, list_id, designer_id);
  task_id := public.ensure_crm_generated_task(p_deal_id, 'QUOTE_PROPOSAL');
  DELETE FROM hrsys_private.crm_quote_proposal_context
  WHERE backend_pid = pg_backend_pid() AND transaction_id = txid_current();

  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE id = task_id AND crm_deal_id = p_deal_id
      AND crm_workflow_kind = 'QUOTE_PROPOSAL' AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Generated task identity mismatch' USING ERRCODE = '23514';
  END IF;

  UPDATE public.crm_deals
  SET design_task_id = task_id, approval_type = 'QUOTE_PROPOSAL',
      workflow_status = 'DESIGN_IN_PROGRESS', proposal_sent_at = COALESCE(proposal_sent_at, now())
  WHERE id = p_deal_id;
  IF NOT already_registered THEN
    INSERT INTO public.crm_deal_activity(deal_id, action, note, actor_id)
    VALUES(p_deal_id, 'QUOTE_PROPOSAL_STARTED', task_id::text, auth.uid());
  END IF;
  RETURN task_id;
END
$body$;

ALTER FUNCTION public.start_crm_quote_proposal(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.start_crm_quote_proposal(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.start_crm_quote_proposal(uuid) TO authenticated, service_role;

DO $verify$
BEGIN
  IF has_function_privilege('anon', 'public.start_crm_quote_proposal(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.start_crm_quote_proposal(uuid)', 'EXECUTE')
     OR NOT EXISTS (
       SELECT 1 FROM pg_proc
       WHERE oid = 'public.start_crm_quote_proposal(uuid)'::regprocedure
         AND proowner = 'postgres'::regrole AND prosecdef
         AND proconfig = ARRAY['search_path=public, pg_temp']::text[]
     ) THEN
    RAISE EXCEPTION 'CRM Quote & Proposal security verification failed';
  END IF;
END
$verify$;

NOTIFY pgrst, 'reload schema';
COMMIT;
