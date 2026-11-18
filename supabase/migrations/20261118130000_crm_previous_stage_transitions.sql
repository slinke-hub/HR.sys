-- Allow an assigned CRM user to return a deal by exactly one open-pipeline stage.
-- Presentation, Won, Lost, and Discussion -> Negotiation remain workflow-controlled.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
BEGIN
  IF to_regprocedure('public.enforce_deal_workflow_transition()') IS NULL
     OR to_regprocedure('public.change_crm_deal_stage(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'CRM stage workflow functions are unavailable';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $body$
DECLARE ready boolean;
BEGIN
  IF NEW.stage = 'LOST' AND NULLIF(BTRIM(COALESCE(NEW.lost_reason,'')),'') IS NULL THEN
    RAISE EXCEPTION 'A lost reason is required' USING ERRCODE='23514';
  END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.stage <> 'LEAD' THEN RAISE EXCEPTION 'New deals must start in Lead' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.stage IS NOT DISTINCT FROM OLD.stage THEN RETURN NEW; END IF;
  IF auth.uid() IS NOT NULL AND (
      NOT coalesce(public.can_access_crm(auth.uid()),false)
      OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false)
      OR (auth.uid() IS DISTINCT FROM OLD.created_by AND auth.uid() IS DISTINCT FROM OLD.assigned_to
          AND NOT auth.uid()=ANY(coalesce(OLD.assignee_ids,'{}'::uuid[])))) THEN
    RAISE EXCEPTION 'Deal assignment required' USING ERRCODE='42501';
  END IF;
  IF (OLD.stage='LEAD' AND NEW.stage='QUALIFICATION')
     OR (OLD.stage='QUALIFICATION' AND NEW.stage IN ('LEAD','DISCUSSION'))
     OR (OLD.stage='DISCUSSION' AND NEW.stage='QUALIFICATION')
     OR (OLD.stage='NEGOTIATION' AND NEW.stage='DISCUSSION') THEN
    RETURN NEW;
  END IF;
  IF OLD.stage='DISCUSSION' AND NEW.stage='NEGOTIATION' THEN
    SELECT EXISTS (SELECT 1 FROM public.crm_generated_tasks m JOIN public.tasks t ON t.id=m.task_id
      WHERE m.deal_id=OLD.id AND m.kind='QUOTE_PROPOSAL' AND t.crm_deal_id=OLD.id
        AND t.crm_workflow_kind='QUOTE_PROPOSAL' AND t.archived_at IS NULL
        AND lower(btrim(t.status))='completed') INTO ready;
    IF NOT ready THEN RAISE EXCEPTION 'Complete the registered Quote & Proposal task first' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF OLD.stage='NEGOTIATION' AND NEW.stage='LOST' THEN RETURN NEW; END IF;
  IF OLD.stage='NEGOTIATION' AND NEW.stage='WON' AND EXISTS (
      SELECT 1 FROM public.projects WHERE deal_id=OLD.id AND source='WON_DEAL') THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Invalid CRM stage transition' USING ERRCODE='23514';
END $body$;

CREATE OR REPLACE FUNCTION public.change_crm_deal_stage(p_deal_id uuid,p_new_stage text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $body$
DECLARE d public.crm_deals%ROWTYPE; next_stage text := upper(btrim(coalesce(p_new_stage,''))); task_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT coalesce(public.can_access_crm(auth.uid()),false)
    OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE='42501';
  END IF;
  IF next_stage NOT IN ('LEAD','QUALIFICATION','DISCUSSION','NEGOTIATION') THEN
    RAISE EXCEPTION 'Use the dedicated order or lost workflow' USING ERRCODE='22023';
  END IF;
  SELECT * INTO d FROM public.crm_deals WHERE id=p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE='P0002'; END IF;
  IF auth.uid() IS DISTINCT FROM d.created_by AND auth.uid() IS DISTINCT FROM d.assigned_to
      AND NOT auth.uid()=ANY(coalesce(d.assignee_ids,'{}'::uuid[])) THEN
    RAISE EXCEPTION 'Deal assignment required' USING ERRCODE='42501';
  END IF;
  IF d.stage IS DISTINCT FROM next_stage THEN
    UPDATE public.crm_deals SET stage=next_stage WHERE id=p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id,action,from_status,to_status,actor_id)
      VALUES(p_deal_id,'STAGE_CHANGED',d.stage,next_stage,auth.uid());
  END IF;
  IF d.stage='LEAD' AND next_stage='QUALIFICATION' THEN
    task_id := public.create_crm_contact_discussion_task(p_deal_id);
  END IF;
  RETURN jsonb_build_object('deal_id',p_deal_id,'from_stage',d.stage,'to_stage',next_stage,'task_id',task_id,'actor_id',auth.uid());
END $body$;

ALTER FUNCTION public.enforce_deal_workflow_transition() OWNER TO postgres;
ALTER FUNCTION public.change_crm_deal_stage(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enforce_deal_workflow_transition() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enforce_deal_workflow_transition() TO authenticated;
REVOKE ALL ON FUNCTION public.change_crm_deal_stage(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_crm_deal_stage(uuid,text) TO authenticated;
COMMIT;
