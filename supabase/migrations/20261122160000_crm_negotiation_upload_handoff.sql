-- Move a Discussion deal to Negotiation atomically after the required CRM
-- Quote & Proposal files are uploaded, and create its configured MQ-08 task.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
BEGIN
  IF to_regprocedure('public.enforce_deal_workflow_transition()') IS NULL
     OR to_regprocedure('public.start_crm_quote_proposal(uuid)') IS NULL
     OR to_regprocedure('public.can_access_crm(uuid)') IS NULL
     OR to_regclass('public.crm_deals') IS NULL
     OR to_regclass('public.crm_deal_attachments') IS NULL
     OR to_regclass('public.crm_generated_tasks') IS NULL
     OR to_regclass('public.tasks') IS NULL THEN
    RAISE EXCEPTION 'CRM Quote & Proposal handoff prerequisites are unavailable';
  END IF;
END
$guard$;

CREATE TABLE IF NOT EXISTS hrsys_private.crm_quote_proposal_request_context (
  backend_pid integer NOT NULL,
  transaction_id bigint NOT NULL,
  actor_id uuid NOT NULL,
  deal_id uuid NOT NULL,
  task_id uuid NOT NULL,
  PRIMARY KEY (backend_pid, transaction_id)
);
ALTER TABLE hrsys_private.crm_quote_proposal_request_context OWNER TO postgres;
REVOKE ALL ON TABLE hrsys_private.crm_quote_proposal_request_context FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION hrsys_private.crm_quote_proposal_request_ready(p_deal_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.crm_generated_tasks mapping
    JOIN public.tasks task ON task.id = mapping.task_id
      AND task.crm_deal_id = mapping.deal_id
      AND task.crm_workflow_kind = 'QUOTE_PROPOSAL'
      AND task.archived_at IS NULL
    WHERE mapping.deal_id = p_deal_id
      AND mapping.kind = 'QUOTE_PROPOSAL'
      AND EXISTS (
        SELECT 1 FROM public.crm_deal_attachments attachment
        WHERE attachment.deal_id = p_deal_id
          AND attachment.category = 'QUOTATION'
          AND attachment.is_archived = false
          AND NULLIF(BTRIM(attachment.file_url), '') IS NOT NULL
      )
      AND EXISTS (
        SELECT 1 FROM public.crm_deal_attachments attachment
        WHERE attachment.deal_id = p_deal_id
          AND attachment.category = 'PROPOSAL'
          AND attachment.is_archived = false
          AND NULLIF(BTRIM(attachment.file_url), '') IS NOT NULL
          AND NULLIF(BTRIM(attachment.description), '') IS NOT NULL
          AND attachment.file_type LIKE 'image/%'
      )
  );
$function$;
ALTER FUNCTION hrsys_private.crm_quote_proposal_request_ready(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.crm_quote_proposal_request_ready(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  internal_completion_transition boolean := false;
  internal_request_transition boolean := false;
  caller_is_admin boolean := false;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id = auth.uid()
      AND profile.is_active IS DISTINCT FROM false
      AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g')))
          IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'SYSTEM ADMINISTRATOR')
  ) INTO caller_is_admin;

  IF NEW.stage = 'LOST' AND NULLIF(BTRIM(COALESCE(NEW.lost_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A lost reason is required' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.stage <> 'LEAD' THEN RAISE EXCEPTION 'New deals must start in Lead' USING ERRCODE = '23514'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.stage IS NOT DISTINCT FROM OLD.stage THEN RETURN NEW; END IF;

  SELECT EXISTS (
    SELECT 1
    FROM hrsys_private.crm_quote_proposal_completion_context context
    JOIN public.crm_generated_tasks mapping ON mapping.deal_id = context.deal_id
      AND mapping.task_id = context.task_id AND mapping.kind = 'QUOTE_PROPOSAL'
    JOIN public.tasks task ON task.id = context.task_id AND task.crm_deal_id = context.deal_id
      AND task.crm_workflow_kind = 'QUOTE_PROPOSAL'
    WHERE context.backend_pid = pg_backend_pid() AND context.transaction_id = txid_current()
      AND context.actor_id = auth.uid() AND context.deal_id = OLD.id
      AND OLD.stage = 'DISCUSSION' AND NEW.stage = 'NEGOTIATION'
      AND hrsys_private.crm_quote_proposal_submission_ready(OLD.id)
  ) INTO internal_completion_transition;

  SELECT EXISTS (
    SELECT 1
    FROM hrsys_private.crm_quote_proposal_request_context context
    JOIN public.crm_generated_tasks mapping ON mapping.deal_id = context.deal_id
      AND mapping.task_id = context.task_id AND mapping.kind = 'QUOTE_PROPOSAL'
    JOIN public.tasks task ON task.id = context.task_id AND task.crm_deal_id = context.deal_id
      AND task.crm_workflow_kind = 'QUOTE_PROPOSAL' AND task.archived_at IS NULL
    WHERE context.backend_pid = pg_backend_pid() AND context.transaction_id = txid_current()
      AND context.actor_id = auth.uid() AND context.deal_id = OLD.id
      AND OLD.stage = 'DISCUSSION' AND NEW.stage = 'NEGOTIATION'
      AND hrsys_private.crm_quote_proposal_request_ready(OLD.id)
  ) INTO internal_request_transition;
  IF internal_completion_transition OR internal_request_transition THEN RETURN NEW; END IF;

  IF auth.uid() IS NOT NULL AND NOT caller_is_admin AND (
      NOT COALESCE(public.can_access_crm(auth.uid()), false)
      OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_active IS DISTINCT FROM false)
      OR (auth.uid() IS DISTINCT FROM OLD.created_by
          AND auth.uid() IS DISTINCT FROM OLD.assigned_to
          AND NOT auth.uid() = ANY(COALESCE(OLD.assignee_ids, '{}'::uuid[])))
  ) THEN RAISE EXCEPTION 'Deal assignment required' USING ERRCODE = '42501'; END IF;

  IF (OLD.stage = 'LEAD' AND NEW.stage = 'QUALIFICATION')
     OR (OLD.stage = 'QUALIFICATION' AND NEW.stage IN ('LEAD', 'DISCUSSION'))
     OR (OLD.stage = 'DISCUSSION' AND NEW.stage = 'QUALIFICATION')
     OR (OLD.stage = 'NEGOTIATION' AND NEW.stage = 'DISCUSSION') THEN RETURN NEW; END IF;
  IF OLD.stage = 'DISCUSSION' AND NEW.stage = 'NEGOTIATION' THEN
    IF NOT hrsys_private.crm_quote_proposal_submission_ready(OLD.id) THEN
      RAISE EXCEPTION 'Submit all required Quote & Proposal fields and files before Negotiation' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.stage = 'NEGOTIATION' AND NEW.stage = 'LOST' THEN RETURN NEW; END IF;
  IF OLD.stage = 'NEGOTIATION' AND NEW.stage = 'WON'
     AND EXISTS (SELECT 1 FROM public.projects WHERE deal_id = OLD.id AND source = 'WON_DEAL') THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Invalid CRM stage transition' USING ERRCODE = '23514';
END
$function$;
ALTER FUNCTION public.enforce_deal_workflow_transition() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enforce_deal_workflow_transition() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enforce_deal_workflow_transition() TO authenticated;

CREATE OR REPLACE FUNCTION public.start_crm_quote_proposal_and_advance(p_deal_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $body$
DECLARE
  current_stage text;
  task_id uuid;
BEGIN
  IF auth.uid() IS NULL
     OR NOT COALESCE(public.can_access_crm(auth.uid()), false)
     OR NOT EXISTS (
       SELECT 1 FROM public.profiles
       WHERE id = auth.uid() AND is_active IS DISTINCT FROM false
     ) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;

  SELECT stage INTO current_stage
  FROM public.crm_deals
  WHERE id = p_deal_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
  IF current_stage <> 'DISCUSSION' THEN
    RAISE EXCEPTION 'Deal must be in Discussion before the Quote & Proposal handoff' USING ERRCODE = '23514';
  END IF;

  -- Reuses the existing secure route validation and creates the MQ-08 task.
  task_id := public.start_crm_quote_proposal(p_deal_id);
  IF task_id IS NULL THEN RAISE EXCEPTION 'Quote & Proposal design task was not created' USING ERRCODE = '23514'; END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.tasks task
    JOIN public.profiles designer ON designer.id = task.assignee_id
      OR designer.id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
    WHERE task.id = task_id
      AND designer.employee_id = 'MQ-08'
      AND designer.is_active IS TRUE
  ) THEN
    RAISE EXCEPTION 'The Quote & Proposal task must be assigned to active Design employee MQ-08' USING ERRCODE = '23514';
  END IF;

  INSERT INTO hrsys_private.crm_quote_proposal_request_context(
    backend_pid, transaction_id, actor_id, deal_id, task_id
  ) VALUES (pg_backend_pid(), txid_current(), auth.uid(), p_deal_id, task_id)
  ON CONFLICT (backend_pid, transaction_id) DO UPDATE
    SET actor_id = EXCLUDED.actor_id, deal_id = EXCLUDED.deal_id, task_id = EXCLUDED.task_id;

  UPDATE public.crm_deals
  SET stage = 'NEGOTIATION'
  WHERE id = p_deal_id AND stage = 'DISCUSSION';
  IF NOT FOUND THEN RAISE EXCEPTION 'Deal stage changed before Quote & Proposal handoff' USING ERRCODE = '40001'; END IF;

  DELETE FROM hrsys_private.crm_quote_proposal_request_context
  WHERE backend_pid = pg_backend_pid() AND transaction_id = txid_current();

  INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
  VALUES (p_deal_id, 'STAGE_CHANGED', 'DISCUSSION', 'NEGOTIATION',
          'Required Quote & Proposal files uploaded; MQ-08 design task created.', auth.uid());
  RETURN task_id;
END
$body$;
ALTER FUNCTION public.start_crm_quote_proposal_and_advance(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.start_crm_quote_proposal_and_advance(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.start_crm_quote_proposal_and_advance(uuid) TO authenticated;

DO $verify$
BEGIN
  IF has_function_privilege('anon', 'public.start_crm_quote_proposal_and_advance(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.start_crm_quote_proposal_and_advance(uuid)', 'EXECUTE')
     OR NOT EXISTS (
       SELECT 1 FROM pg_proc
       WHERE oid = 'public.start_crm_quote_proposal_and_advance(uuid)'::regprocedure
         AND proowner = 'postgres'::regrole AND prosecdef
         AND proconfig = ARRAY['search_path=public, pg_temp']::text[]
     )
     OR has_function_privilege('authenticated', 'hrsys_private.crm_quote_proposal_request_ready(uuid)', 'EXECUTE')
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgrelid = 'public.crm_deals'::regclass
         AND tgfoid = 'public.enforce_deal_workflow_transition()'::regprocedure
         AND NOT tgisinternal
     ) THEN
    RAISE EXCEPTION 'CRM Quote & Proposal Negotiation handoff security verification failed';
  END IF;
END
$verify$;

NOTIFY pgrst, 'reload schema';
COMMIT;
