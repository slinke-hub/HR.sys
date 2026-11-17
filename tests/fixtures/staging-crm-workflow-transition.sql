-- Exact data-free Staging catalog function and trigger definitions; export 2026-11-09.
CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.stage = 'NEGOTIATION' AND (TG_OP = 'INSERT' OR OLD.stage IS DISTINCT FROM NEW.stage) THEN
    RAISE EXCEPTION 'Discussion is no longer an active CRM stage' USING ERRCODE = '23514';
  END IF;
  IF NEW.stage = 'LOST' AND NULLIF(BTRIM(COALESCE(NEW.lost_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A lost reason is required' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER crm_deal_workflow_transition BEFORE INSERT OR UPDATE OF stage, workflow_status, lost_reason ON crm_deals FOR EACH ROW EXECUTE FUNCTION enforce_deal_workflow_transition();
