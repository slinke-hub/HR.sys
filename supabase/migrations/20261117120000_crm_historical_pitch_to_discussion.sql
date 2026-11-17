-- Reviewed one-time transition of the twelve existing Production PITCH deals.
-- Historical approvals and documents are retained; new Quote & Proposal work
-- remains subject to the normal registered-task and Negotiation guards.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
LOCK TABLE public.crm_deals IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.crm_deal_approval_steps IN SHARE MODE;
LOCK TABLE public.crm_deal_attachments IN SHARE MODE;
LOCK TABLE public.crm_deal_activity IN SHARE ROW EXCLUSIVE MODE;
DO $transition$
DECLARE original text; patched text; needle text; approval_before text; attachment_before text; changed integer; activity_before bigint; target_ids uuid[]; activity_ids uuid[]; activity_hash text; deal_hash text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR current_database()<>'postgres' OR auth.uid() IS NOT NULL THEN
  RAISE EXCEPTION 'Historical transition requires the verified administrator session';
 END IF;
 IF to_regclass('supabase_migrations.schema_migrations') IS NULL THEN RAISE EXCEPTION 'Migration ledger unavailable'; END IF;
 IF EXISTS (SELECT 1 FROM unnest(ARRAY['20261111100000','20261112100000','20261112110000','20261112120000','20261113100000','20261115120000','20261117110000']) expected(version) WHERE (SELECT count(*) FROM supabase_migrations.schema_migrations m WHERE m.version=expected.version)<>1) OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261117120000') THEN
  RAISE EXCEPTION 'Required migration ledger state differs';
 END IF;
 IF to_regprocedure('public.enforce_deal_workflow_transition()') IS NULL OR
    md5(replace(pg_get_functiondef('public.enforce_deal_workflow_transition()'::regprocedure),E'\r\n',E'\n'))<>'68b0ad8b0ec9833ce73646d6786ffdda' OR
    NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.enforce_deal_workflow_transition()'::regprocedure AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp']) THEN
  RAISE EXCEPTION 'Reviewed transition guard differs';
 END IF;
 IF (SELECT count(*) FROM public.crm_deals WHERE stage='PITCH')<>12 OR EXISTS (
  SELECT 1 FROM public.crm_deals WHERE stage='PITCH' AND
    (workflow_status IS DISTINCT FROM 'PENDING_APPROVAL' OR approval_type IS DISTINCT FROM 'QUOTE' OR design_task_id IS NOT NULL OR first_contact_date IS NULL OR nullif(btrim(coalesce(contact_method,'')),'') IS NULL)
 ) THEN RAISE EXCEPTION 'Historical deal baseline differs; review before migration'; END IF;
 IF (SELECT count(*) FROM public.crm_deal_approval_steps s JOIN public.crm_deals d ON d.id=s.deal_id WHERE d.stage='PITCH')<>36 THEN
  RAISE EXCEPTION 'Historical approval count differs; review before migration';
 END IF;
 IF (SELECT count(*) FROM public.crm_deal_attachments a JOIN public.crm_deals d ON d.id=a.deal_id WHERE d.stage='PITCH')<>12 OR
    (SELECT count(*) FROM public.crm_deal_attachments a JOIN public.crm_deals d ON d.id=a.deal_id WHERE d.stage='PITCH' AND a.category='QUOTATION')<>12 THEN
  RAISE EXCEPTION 'Historical document baseline differs; review before migration';
 END IF;
 IF (SELECT count(*) FROM public.crm_deal_activity a JOIN public.crm_deals d ON d.id=a.deal_id WHERE d.stage='PITCH')<>52 THEN
  RAISE EXCEPTION 'Historical activity baseline differs; review before migration';
 END IF;
 IF EXISTS (SELECT 1 FROM public.crm_generated_tasks m JOIN public.crm_deals d ON d.id=m.deal_id WHERE d.stage='PITCH' AND m.kind IN ('QUOTE_PROPOSAL','QUOTE_PROPOSAL_DESIGN')) THEN
  RAISE EXCEPTION 'Historical Design task mapping requires review';
 END IF;
 SELECT array_agg(id ORDER BY id), md5(coalesce(string_agg(md5((to_jsonb(d)-'stage'-'workflow_status')::text),'' ORDER BY id),'')) INTO target_ids,deal_hash FROM public.crm_deals d WHERE stage='PITCH';
 SELECT array_agg(id ORDER BY id), md5(coalesce(string_agg(md5(to_jsonb(a)::text),'' ORDER BY id),'')) INTO activity_ids, activity_hash FROM public.crm_deal_activity a WHERE deal_id=ANY(target_ids);
 SELECT md5(coalesce(string_agg(md5(to_jsonb(s)::text),'' ORDER BY s.id),'')) INTO approval_before FROM public.crm_deal_approval_steps s JOIN public.crm_deals d ON d.id=s.deal_id WHERE d.stage='PITCH';
 SELECT md5(coalesce(string_agg(md5(to_jsonb(a)::text),'' ORDER BY a.id),'')) INTO attachment_before FROM public.crm_deal_attachments a JOIN public.crm_deals d ON d.id=a.deal_id WHERE d.stage='PITCH';
 SELECT count(*) INTO activity_before FROM public.crm_deal_activity;
 original:=pg_get_functiondef('public.enforce_deal_workflow_transition()'::regprocedure);
 needle:='  IF OLD.stage=''LEAD'' AND NEW.stage=''QUALIFICATION'' THEN RETURN NEW; END IF;';
 patched:=replace(original,needle,'  IF session_user=''postgres'' AND auth.uid() IS NULL AND OLD.stage=''PITCH'' AND NEW.stage=''DISCUSSION'' AND OLD.workflow_status=''PENDING_APPROVAL'' AND NEW.workflow_status=''NOT_STARTED'' THEN RETURN NEW; END IF;'||E'\n'||needle);
 IF patched=original THEN RAISE EXCEPTION 'Reviewed transition insertion point missing'; END IF;
 EXECUTE patched;
 WITH moved AS (
  UPDATE public.crm_deals SET stage='DISCUSSION',workflow_status='NOT_STARTED'
  WHERE id=ANY(target_ids) AND stage='PITCH' AND workflow_status='PENDING_APPROVAL' AND approval_type='QUOTE' AND design_task_id IS NULL
  RETURNING id
 ) INSERT INTO public.crm_deal_activity(deal_id,action,from_status,to_status,note,actor_id)
 SELECT id,'STAGE_CHANGED','PITCH','DISCUSSION','Historical workflow moved to Discussion for new Quote & Proposal',NULL FROM moved;
 GET DIAGNOSTICS changed=ROW_COUNT;
 EXECUTE original;
 IF changed<>12 OR (SELECT count(*) FROM public.crm_deals WHERE id=ANY(target_ids) AND stage='DISCUSSION' AND workflow_status='NOT_STARTED')<>12 OR EXISTS(SELECT 1 FROM public.crm_deals WHERE stage='PITCH') OR
    md5(replace(pg_get_functiondef('public.enforce_deal_workflow_transition()'::regprocedure),E'\r\n',E'\n'))<>'68b0ad8b0ec9833ce73646d6786ffdda' THEN
  RAISE EXCEPTION 'Historical transition or guard restoration failed';
 END IF;
 IF (SELECT md5(coalesce(string_agg(md5((to_jsonb(d)-'stage'-'workflow_status')::text),'' ORDER BY id),'')) FROM public.crm_deals d WHERE id=ANY(target_ids))<>deal_hash OR
    (SELECT count(*) FROM public.crm_deal_activity)<>activity_before+12 OR
    (SELECT md5(coalesce(string_agg(md5(to_jsonb(a)::text),'' ORDER BY id),'')) FROM public.crm_deal_activity a WHERE id=ANY(activity_ids))<>activity_hash OR
    (SELECT md5(coalesce(string_agg(md5(to_jsonb(s)::text),'' ORDER BY s.id),'')) FROM public.crm_deal_approval_steps s JOIN public.crm_deals d ON d.id=s.deal_id WHERE s.deal_id=ANY(target_ids))<>approval_before OR
    (SELECT md5(coalesce(string_agg(md5(to_jsonb(a)::text),'' ORDER BY a.id),'')) FROM public.crm_deal_attachments a JOIN public.crm_deals d ON d.id=a.deal_id WHERE a.deal_id=ANY(target_ids))<>attachment_before THEN
  RAISE EXCEPTION 'Historical approval, document, or activity preservation failed';
 END IF;
END $transition$;
COMMIT;
