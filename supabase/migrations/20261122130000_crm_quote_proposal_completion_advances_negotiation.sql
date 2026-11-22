-- Advance a Discussion deal only after its registered Quote & Proposal task is
-- completed with all required source and design files still present.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
BEGIN
  IF to_regprocedure('public.enforce_deal_workflow_transition()') IS NULL
     OR to_regclass('public.crm_generated_tasks') IS NULL
     OR to_regclass('public.task_attachments') IS NULL
     OR to_regclass('hrsys_private.crm_quote_proposal_context') IS NULL THEN
    RAISE EXCEPTION 'CRM Quote & Proposal workflow prerequisites are unavailable';
  END IF;
END
$guard$;

CREATE TABLE IF NOT EXISTS hrsys_private.crm_quote_proposal_completion_context (
  backend_pid integer NOT NULL,
  transaction_id bigint NOT NULL,
  actor_id uuid NOT NULL,
  deal_id uuid NOT NULL,
  task_id uuid NOT NULL,
  PRIMARY KEY (backend_pid, transaction_id)
);
REVOKE ALL ON TABLE hrsys_private.crm_quote_proposal_completion_context FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION hrsys_private.crm_quote_proposal_submission_ready(p_deal_id uuid)
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
      AND LOWER(BTRIM(COALESCE(task.status, ''))) = 'completed'
    WHERE mapping.deal_id = p_deal_id
      AND mapping.kind = 'QUOTE_PROPOSAL'
      AND COALESCE(CARDINALITY(task.submission_links), 0) > 0
      AND EXISTS (
        SELECT 1 FROM public.crm_deal_attachments source_file
        WHERE source_file.deal_id = p_deal_id AND source_file.category = 'QUOTATION'
          AND source_file.is_archived = false AND NULLIF(BTRIM(source_file.file_url), '') IS NOT NULL
      )
      AND EXISTS (
        SELECT 1 FROM public.crm_deal_attachments source_file
        WHERE source_file.deal_id = p_deal_id AND source_file.category = 'PROPOSAL'
          AND source_file.is_archived = false AND NULLIF(BTRIM(source_file.file_url), '') IS NOT NULL
          AND NULLIF(BTRIM(source_file.description), '') IS NOT NULL AND source_file.file_type LIKE 'image/%'
      )
      AND NOT EXISTS (
        SELECT 1 FROM UNNEST(task.submission_links) submitted_link
        WHERE NOT EXISTS (
          SELECT 1 FROM public.task_attachments attachment
          WHERE attachment.task_id = task.id AND attachment.file_url = submitted_link
            AND attachment.is_archived = false
            AND (attachment.file_type = 'application/pdf' OR attachment.file_type LIKE 'image/%')
        )
      )
  );
$function$;
ALTER FUNCTION hrsys_private.crm_quote_proposal_submission_ready(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.crm_quote_proposal_submission_ready(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE internal_completion_transition boolean := false;
BEGIN
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
      AND LOWER(BTRIM(COALESCE(task.status, ''))) = 'completed'
    WHERE context.backend_pid = pg_backend_pid() AND context.transaction_id = txid_current()
      AND context.actor_id = auth.uid() AND context.deal_id = OLD.id
      AND OLD.stage = 'DISCUSSION' AND NEW.stage = 'NEGOTIATION'
      AND hrsys_private.crm_quote_proposal_submission_ready(OLD.id)
  ) INTO internal_completion_transition;
  IF internal_completion_transition THEN RETURN NEW; END IF;

  IF auth.uid() IS NOT NULL AND (
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
      RAISE EXCEPTION 'Complete all required Quote & Proposal fields and files before Negotiation' USING ERRCODE = '23514';
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

CREATE OR REPLACE FUNCTION public.advance_crm_deal_after_quote_proposal_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE deal_stage text;
BEGIN
  IF NEW.crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL'
     OR NEW.crm_deal_id IS NULL
     OR LOWER(BTRIM(COALESCE(NEW.status, ''))) <> 'completed'
     OR LOWER(BTRIM(COALESCE(OLD.status, ''))) = 'completed' THEN RETURN NEW; END IF;

  IF auth.uid() IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_active IS DISTINCT FROM false
     ) OR NOT (
       auth.uid() = NEW.assignee_id
       OR auth.uid() = ANY(COALESCE(NEW.assignee_ids, '{}'::uuid[]))
       OR public.can_manage_task(NEW.id, auth.uid())
     ) THEN
    RAISE EXCEPTION 'Assigned active employee or task manager required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.crm_generated_tasks mapping
    WHERE mapping.deal_id = NEW.crm_deal_id AND mapping.task_id = NEW.id AND mapping.kind = 'QUOTE_PROPOSAL'
  ) OR NOT hrsys_private.crm_quote_proposal_submission_ready(NEW.crm_deal_id) THEN
    RAISE EXCEPTION 'Complete all required Quote & Proposal fields and files before Negotiation' USING ERRCODE = '23514';
  END IF;

  SELECT stage INTO deal_stage FROM public.crm_deals WHERE id = NEW.crm_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
  IF deal_stage = 'NEGOTIATION' THEN RETURN NEW; END IF;
  IF deal_stage <> 'DISCUSSION' THEN
    RAISE EXCEPTION 'Quote & Proposal task can advance only a Discussion deal' USING ERRCODE = '23514';
  END IF;

  INSERT INTO hrsys_private.crm_quote_proposal_completion_context(backend_pid, transaction_id, actor_id, deal_id, task_id)
  VALUES (pg_backend_pid(), txid_current(), auth.uid(), NEW.crm_deal_id, NEW.id)
  ON CONFLICT (backend_pid, transaction_id) DO UPDATE
    SET actor_id = EXCLUDED.actor_id, deal_id = EXCLUDED.deal_id, task_id = EXCLUDED.task_id;
  UPDATE public.crm_deals SET stage = 'NEGOTIATION' WHERE id = NEW.crm_deal_id AND stage = 'DISCUSSION';
  IF NOT FOUND THEN RAISE EXCEPTION 'Deal stage changed before Quote & Proposal completion' USING ERRCODE = '40001'; END IF;
  DELETE FROM hrsys_private.crm_quote_proposal_completion_context
  WHERE backend_pid = pg_backend_pid() AND transaction_id = txid_current();
  INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
  VALUES (NEW.crm_deal_id, 'STAGE_CHANGED', 'DISCUSSION', 'NEGOTIATION', 'Required Quote & Proposal task completed.', auth.uid());
  RETURN NEW;
END
$function$;
ALTER FUNCTION public.advance_crm_deal_after_quote_proposal_completion() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.advance_crm_deal_after_quote_proposal_completion() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS crm_quote_proposal_completion_advances_deal ON public.tasks;
CREATE TRIGGER crm_quote_proposal_completion_advances_deal
AFTER UPDATE OF status ON public.tasks
FOR EACH ROW
WHEN (NEW.crm_workflow_kind = 'QUOTE_PROPOSAL' AND LOWER(BTRIM(COALESCE(NEW.status, ''))) = 'completed')
EXECUTE FUNCTION public.advance_crm_deal_after_quote_proposal_completion();

DO $verify$
BEGIN
  IF has_function_privilege('anon', 'public.enforce_deal_workflow_transition()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.enforce_deal_workflow_transition()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.advance_crm_deal_after_quote_proposal_completion()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.advance_crm_deal_after_quote_proposal_completion()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'hrsys_private.crm_quote_proposal_submission_ready(uuid)', 'EXECUTE')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.tasks'::regclass
       AND tgname = 'crm_quote_proposal_completion_advances_deal' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CRM Quote & Proposal completion transition security verification failed';
  END IF;
END
$verify$;

NOTIFY pgrst, 'reload schema';
COMMIT;
