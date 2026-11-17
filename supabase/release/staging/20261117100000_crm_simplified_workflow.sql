-- LOCAL DRAFT: Staging-derived baseline only. Do not apply to hosted databases.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
DECLARE item record;
BEGIN
  IF current_user <> 'postgres' OR current_setting('server_version_num')::int NOT BETWEEN 170000 AND 179999 THEN
    RAISE EXCEPTION 'Unexpected migration role or PostgreSQL version';
  END IF;
  FOR item IN SELECT * FROM (VALUES
    ('public.ensure_crm_generated_task(uuid,text)','f4cf0fe7a527b44e5f4f51ca3b1b17bd'),
    ('public.protect_crm_generated_task_identity()','f87b9f595740451bae82009de5243555'),
    ('public.enforce_task_completion_approval()','95bf4cbd39d3f0d3fca597bde8ed2a7f'),
    ('public.enforce_marketing_design_review()','5de3c67d0dfecfd1d0cef8e338cf482d'),
    ('public.enforce_private_task_list_ownership()','2aaa8c5edb6569dc16b5eaf76780b058'),
    ('public.can_read_crm_deal_file(text,uuid)','59a03bfe102fa169718a67d5d9072b76'),
    ('public.list_crm_deal_attachments_secure(uuid)','9727df25ed36adb01d231c1f0da33f0c'),
    ('public.can_access_task(uuid,uuid)','a7bd4e222376bcda23e5c7286e9cd553'),
    ('public.can_view_task(uuid,uuid)','efe4475c86c7b975e2e2d66dae2cfde1'),
    ('public.can_manage_task(uuid,uuid)','fc68835f04169ad89d1f052dd0984ee2'),
    ('public.can_manage_task_attachments(uuid,uuid)','1a9d5dd09b536d631f8fe10bf18353a6'),
    ('public.change_task_status(uuid,text)','7bbec9375587105ee0be9350a42e4b58'),
    ('public.can_delete_task(uuid,uuid)','d533732c5a60263f82f2e593e15e37e0'),
    ('public.can_execute_task(uuid,uuid)','6f72cf446da10b7f78cf49849a98f440'),
    ('public.delete_task_secure(uuid)','6e970986266bf96e8067521109ec3821'),
    ('public.task_belongs_to_employee(uuid,uuid)','4db3b76077aaebc28fc71a95625455eb'),
    ('public.enforce_crm_design_task_completion()','ba4ad683421f6cbee33d11be636cfd5f'),
    ('public.sync_crm_design_task_status()','d04129cd545a6410257e28de9fe2c1de'),
    ('public.enforce_deal_workflow_transition()','d9b91256d5a5bd9c4f9494e64131598b'),
    ('public.change_crm_deal_stage(uuid,text)','a8264b38b7d76ee225803775fa6e4d32')
  ) x(signature,fingerprint) LOOP
    IF to_regprocedure(item.signature) IS NULL OR
       md5(replace(pg_get_functiondef(to_regprocedure(item.signature)),E'\r\n',E'\n')) <> item.fingerprint OR
       NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(item.signature)
         AND p.proowner='postgres'::regrole AND p.proconfig=ARRAY['search_path=public, pg_temp']
         AND p.prosecdef=(item.signature <> 'public.enforce_deal_workflow_transition()')) THEN
      RAISE EXCEPTION 'Baseline fingerprint mismatch: %',item.signature;
    END IF;
  END LOOP;
  IF to_regprocedure('public.start_crm_quote_proposal(uuid)') IS NOT NULL
     OR to_regclass('hrsys_private.crm_quote_proposal_context') IS NOT NULL
     OR to_regprocedure('hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)') IS NOT NULL
     OR to_regprocedure('hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[])') IS NOT NULL
     OR to_regprocedure('hrsys_private.can_read_quote_proposal_source(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Quote & Proposal RPC already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.tasks'::regclass AND polname='tasks_select_own_created'
    AND polcmd='r' AND polpermissive AND md5(pg_get_expr(polqual,polrelid))='987767fc803474751ce44a4235a12922') THEN
    RAISE EXCEPTION 'Task creator read policy differs from baseline';
  END IF;
  IF has_function_privilege('anon','public.change_crm_deal_stage(uuid,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.change_crm_deal_stage(uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public.ensure_crm_generated_task(uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.ensure_crm_generated_task(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Workflow execution grants differ';
  END IF;
  IF to_regprocedure('public.enforce_mq20_task_service_boundaries()') IS NULL OR
    md5(replace(pg_get_functiondef('public.enforce_mq20_task_service_boundaries()'::regprocedure),E'\r\n',E'\n'))
      NOT IN ('6eeff07ec9f9d30d63e06c341bc0700f','7a2b93f1e12e3d4ed20fa52ccbb0d972') OR
    NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.enforce_mq20_task_service_boundaries()'::regprocedure
      AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=public, pg_temp']) THEN
    RAISE EXCEPTION 'MQ-20 service boundary differs from reviewed baseline';
  END IF;
  IF md5(replace(pg_get_functiondef('public.start_deal_approval(uuid,uuid,uuid,uuid)'::regprocedure),E'\r\n',E'\n')) <> '6ad663afc289e5e28d04e15581160f05'
    OR md5(replace(pg_get_functiondef('public.start_crm_presentation_approval(uuid,text)'::regprocedure),E'\r\n',E'\n')) <> '326c96ee0119dc57fbcdb8f9ee3c81d3'
    OR md5(replace(pg_get_functiondef('public.decide_deal_approval(uuid,text,text)'::regprocedure),E'\r\n',E'\n')) NOT IN ('497827d94d1debbad4d20fac851e782d','816e58769161345e8e00d4f468d358f3')
    OR md5(replace(pg_get_functiondef('public.decide_crm_design_task_approval(uuid,text,text)'::regprocedure),E'\r\n',E'\n')) <> '8b08289b008d1305180e30ce8de2af37' THEN
    RAISE EXCEPTION 'Historical CRM approval mutation fingerprint mismatch';
  END IF;
END $guard$;

ALTER TABLE public.crm_deals DROP CONSTRAINT crm_deals_stage_check;
ALTER TABLE public.crm_deals ADD CONSTRAINT crm_deals_stage_check
  CHECK (stage IN ('LEAD','QUALIFICATION','DISCUSSION','PITCH','PROPOSAL','NEGOTIATION','WON','LOST'));
ALTER TABLE public.tasks DROP CONSTRAINT tasks_crm_workflow_kind_check;
ALTER TABLE public.tasks ADD CONSTRAINT tasks_crm_workflow_kind_check
  CHECK (crm_workflow_kind IS NULL OR crm_workflow_kind IN ('CONTACT_DISCUSSION','QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL'));
ALTER TABLE public.crm_generated_tasks DROP CONSTRAINT crm_generated_tasks_kind_check;
ALTER TABLE public.crm_generated_tasks ADD CONSTRAINT crm_generated_tasks_kind_check
  CHECK (kind IN ('CONTACT_DISCUSSION','QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL'));

-- This private, transaction-bound capability can only be minted by the
-- authenticated CRM RPC below. It does not grant list permissions to callers.
CREATE TABLE hrsys_private.crm_quote_proposal_context (
  backend_pid integer NOT NULL, transaction_id bigint NOT NULL,
  actor_id uuid NOT NULL, deal_id uuid NOT NULL, list_id uuid NOT NULL,
  designer_id uuid NOT NULL, PRIMARY KEY (backend_pid,transaction_id)
);
REVOKE ALL ON hrsys_private.crm_quote_proposal_context FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hrsys_private.valid_crm_quote_proposal_context(p_deal_id uuid,p_list_id uuid,p_task_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
  SELECT EXISTS (
    SELECT 1 FROM hrsys_private.crm_quote_proposal_context c
     JOIN public.task_lists l ON l.id=c.list_id
     JOIN public.departments department ON department.id=l.department_id
     JOIN public.profiles designer ON designer.id=c.designer_id
    WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current()
      AND c.actor_id=auth.uid() AND c.deal_id=p_deal_id AND c.list_id=p_list_id
      AND designer.is_active IS DISTINCT FROM false AND designer.emp_index=8
      AND designer.department_id=l.department_id AND department.is_active IS DISTINCT FROM false
      AND coalesce(l.name,'') ~* '(design|تصميم)'
      AND (p_task_id IS NULL OR EXISTS (SELECT 1 FROM public.crm_generated_tasks m
        WHERE m.task_id=p_task_id AND m.deal_id=c.deal_id AND m.kind='QUOTE_PROPOSAL'))
  );
$body$;
ALTER FUNCTION hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Only the active, current assignee of the registered, non-archived task may
-- access its quotation and proposal sources. This is not a general CRM grant.
CREATE FUNCTION hrsys_private.can_read_quote_proposal_source(p_deal_id uuid,p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
  SELECT p_user_id IS NOT NULL AND p_user_id=auth.uid() AND EXISTS (
    SELECT 1 FROM public.crm_generated_tasks m
      JOIN public.tasks t ON t.id=m.task_id AND t.crm_deal_id=m.deal_id AND t.crm_workflow_kind=m.kind
      JOIN public.profiles p ON p.id=p_user_id
      JOIN public.task_lists l ON l.id=t.task_list_id
      JOIN public.departments department ON department.id=l.department_id
    WHERE m.deal_id=p_deal_id AND m.kind='QUOTE_PROPOSAL' AND t.archived_at IS NULL
      AND p.is_active IS DISTINCT FROM false
      AND p.department_id=l.department_id AND department.is_active IS DISTINCT FROM false AND coalesce(l.name,'') ~* '(design|تصميم)'
      AND (t.assignee_id=p_user_id OR p_user_id=ANY(coalesce(t.assignee_ids,'{}'::uuid[])))
  );
$body$;
ALTER FUNCTION hrsys_private.can_read_quote_proposal_source(uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.can_read_quote_proposal_source(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- The existing assign_task RPC allows a creator to reassign their own task.
-- For this generated task only, accept assignments to active Design-list
-- department members without granting the creator general list access.
CREATE FUNCTION hrsys_private.valid_crm_quote_proposal_reassignment(p_task_id uuid,p_list_id uuid,p_assignees uuid[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
  SELECT auth.uid() IS NOT NULL AND coalesce(public.can_access_crm(auth.uid()),false) AND EXISTS (
    SELECT 1 FROM public.tasks t JOIN public.crm_generated_tasks m ON m.task_id=t.id AND m.deal_id=t.crm_deal_id AND m.kind=t.crm_workflow_kind
      JOIN public.task_lists l ON l.id=t.task_list_id JOIN public.profiles actor ON actor.id=auth.uid()
      JOIN public.departments department ON department.id=l.department_id
    WHERE t.id=p_task_id AND t.task_list_id=p_list_id AND t.crm_workflow_kind='QUOTE_PROPOSAL'
      AND t.archived_at IS NULL AND t.created_by=auth.uid() AND actor.is_active IS DISTINCT FROM false
      AND department.is_active IS DISTINCT FROM false AND coalesce(l.name,'') ~* '(design|تصميم)'
      AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p_assignees,'{}'::uuid[])) candidate(id)
        LEFT JOIN public.profiles p ON p.id=candidate.id
        WHERE p.id IS NULL OR p.is_active IS FALSE OR p.department_id IS DISTINCT FROM l.department_id)
  );
$body$;
ALTER FUNCTION hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[]) FROM PUBLIC,anon,authenticated,service_role;

-- Extend existing guards to cover the new identity without weakening the
-- historical identities, task-list authorization, or MQ-20 protections.
DO $patch$
DECLARE item record; definition text; updated text;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('public.enforce_mq20_task_service_boundaries()', $$IF TG_TABLE_NAME = 'tasks' THEN$$, $$IF TG_TABLE_NAME = 'tasks' THEN
    IF TG_OP='INSERT' AND NEW.crm_workflow_kind='QUOTE_PROPOSAL' AND NEW.created_by=caller_id
       AND NEW.assignee_id=(SELECT c.designer_id FROM hrsys_private.crm_quote_proposal_context c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current())
       AND NEW.assignee_ids=ARRAY[NEW.assignee_id]::uuid[]
       AND hrsys_private.valid_crm_quote_proposal_context(NEW.crm_deal_id,NEW.task_list_id,NEW.id) THEN RETURN NEW; END IF;
    IF TG_OP='UPDATE' AND OLD.crm_workflow_kind='QUOTE_PROPOSAL'
       AND NEW.assignee_id IS NOT DISTINCT FROM (coalesce(NEW.assignee_ids,'{}'::uuid[]))[1]
       AND (to_jsonb(NEW)-ARRAY['assignee_id','assignee_ids','updated_at'])=(to_jsonb(OLD)-ARRAY['assignee_id','assignee_ids','updated_at'])
       AND hrsys_private.valid_crm_quote_proposal_reassignment(OLD.id,OLD.task_list_id,NEW.assignee_ids) THEN RETURN NEW; END IF;$$),
    ('public.ensure_crm_generated_task(uuid,text)', $$p_kind = 'QUOTE_PROPOSAL_DESIGN'$$, $$p_kind IN ('QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL')$$),
    ('public.ensure_crm_generated_task(uuid,text)', $$NOT COALESCE(public.can_add_task_to_list(v_list, auth.uid()), false)$$, $$(NOT COALESCE(public.can_add_task_to_list(v_list, auth.uid()), false) AND NOT (p_kind='QUOTE_PROPOSAL' AND hrsys_private.valid_crm_quote_proposal_context(p_deal_id,v_list,NULL)))$$),
    ('public.protect_crm_generated_task_identity()', $$'CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN'$$, $$'CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN', 'QUOTE_PROPOSAL'$$),
    ('public.enforce_task_completion_approval()', $$'CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN'$$, $$'CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN', 'QUOTE_PROPOSAL'$$),
    ('public.enforce_marketing_design_review()', $$NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'$$, $$NEW.crm_workflow_kind IN ('QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL')$$),
    ('public.enforce_crm_design_task_completion()', $$NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'$$, $$NEW.crm_workflow_kind IN ('QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL')$$),
    ('public.enforce_private_task_list_ownership()', $$NOT COALESCE(public.can_add_task_to_list(NEW.task_list_id, auth.uid()), false)$$, $$(NOT COALESCE(public.can_add_task_to_list(NEW.task_list_id, auth.uid()), false) AND NOT COALESCE(((TG_OP='INSERT' AND NEW.crm_workflow_kind='QUOTE_PROPOSAL' AND NEW.created_by=auth.uid() AND NEW.assignee_id=(SELECT c.designer_id FROM hrsys_private.crm_quote_proposal_context c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current()) AND NEW.assignee_ids=ARRAY[NEW.assignee_id]::uuid[] AND hrsys_private.valid_crm_quote_proposal_context(NEW.crm_deal_id,NEW.task_list_id,NEW.id)) OR (TG_OP='UPDATE' AND NEW.assignee_id IS NOT DISTINCT FROM (coalesce(NEW.assignee_ids,'{}'::uuid[]))[1] AND (to_jsonb(NEW)-ARRAY['assignee_id','assignee_ids','updated_at'])=(to_jsonb(OLD)-ARRAY['assignee_id','assignee_ids','updated_at']) AND hrsys_private.valid_crm_quote_proposal_reassignment(OLD.id,OLD.task_list_id,NEW.assignee_ids))),false))$$),
    ('public.list_crm_deal_attachments_secure(uuid)', $$AND auth.uid() IS NOT NULL AND public.can_access_crm(auth.uid())$$, $$AND auth.uid() IS NOT NULL AND (public.can_access_crm(auth.uid()) OR (attachment.category IN ('QUOTATION','PROPOSAL') AND hrsys_private.can_read_quote_proposal_source(attachment.deal_id,auth.uid())))$$),
    ('public.can_read_crm_deal_file(text,uuid)', $$IF public.can_access_crm(p_user_id) THEN RETURN true; END IF;$$, $$IF public.can_access_crm(p_user_id) THEN RETURN true; END IF;
  IF EXISTS (SELECT 1 FROM public.crm_deal_attachments attachment WHERE attachment.file_url='storage://crm-deal-files/' || p_object_name
      AND attachment.is_archived=false AND attachment.category IN ('QUOTATION','PROPOSAL')
      AND hrsys_private.can_read_quote_proposal_source(attachment.deal_id,p_user_id)) THEN RETURN true; END IF;$$),
    ('public.can_access_task(uuid,uuid)', $$task.created_by = p_user_id$$, $$(task.created_by = p_user_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.can_view_task(uuid,uuid)', $$p_user_id IN (t.created_by, t.assignee_id, t.supervisor_id)$$, $$(p_user_id IN (t.assignee_id, t.supervisor_id) OR (p_user_id=t.created_by AND coalesce(t.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL'))$$),
    ('public.can_manage_task(uuid,uuid)', $$task.created_by = p_user_id$$, $$(task.created_by = p_user_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.can_manage_task_attachments(uuid,uuid)', $$task.created_by = p_user_id$$, $$(task.created_by = p_user_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.change_task_status(uuid,text)', $$profile.id IN (task_row.created_by, task_row.assignee_id, task_row.supervisor_id)$$, $$(profile.id IN (task_row.assignee_id, task_row.supervisor_id) OR (profile.id=task_row.created_by AND coalesce(task_row.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL'))$$),
    ('public.can_delete_task(uuid,uuid)', $$task.created_by = p_user_id$$, $$(task.created_by = p_user_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.can_execute_task(uuid,uuid)', $$profile.id IN (task.created_by, task.assignee_id, task.supervisor_id)$$, $$(profile.id IN (task.assignee_id, task.supervisor_id) OR (profile.id=task.created_by AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL'))$$),
    ('public.delete_task_secure(uuid)', $$v_task.created_by = auth.uid()$$, $$(v_task.created_by = auth.uid() AND coalesce(v_task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.task_belongs_to_employee(uuid,uuid)', $$task.created_by = p_employee_id$$, $$(task.created_by = p_employee_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.sync_crm_design_task_status()', $$NEW.crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL_DESIGN'$$, $$(NEW.crm_workflow_kind IS NULL OR NEW.crm_workflow_kind NOT IN ('QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL'))$$)
  ) x(signature,old_text,new_text) LOOP
    definition := pg_get_functiondef(to_regprocedure(item.signature));
    updated := replace(definition,item.old_text,item.new_text);
    IF updated = definition THEN RAISE EXCEPTION 'Expected guard insertion point missing: %',item.signature; END IF;
    EXECUTE updated;
  END LOOP;
END $patch$;
ALTER POLICY tasks_select_own_created ON public.tasks
  USING (created_by=auth.uid() AND crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL');

CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
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
  IF OLD.stage='LEAD' AND NEW.stage='QUALIFICATION' THEN RETURN NEW; END IF;
  IF OLD.stage='QUALIFICATION' AND NEW.stage='DISCUSSION' THEN RETURN NEW; END IF;
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
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
DECLARE d public.crm_deals%ROWTYPE; next_stage text := upper(btrim(coalesce(p_new_stage,''))); task_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT coalesce(public.can_access_crm(auth.uid()),false)
    OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE='42501'; END IF;
  IF next_stage NOT IN ('QUALIFICATION','DISCUSSION','NEGOTIATION') THEN
    RAISE EXCEPTION 'Use the dedicated order or lost workflow' USING ERRCODE='22023'; END IF;
  SELECT * INTO d FROM public.crm_deals WHERE id=p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE='P0002'; END IF;
  IF auth.uid() IS DISTINCT FROM d.created_by AND auth.uid() IS DISTINCT FROM d.assigned_to
      AND NOT auth.uid()=ANY(coalesce(d.assignee_ids,'{}'::uuid[])) THEN
    RAISE EXCEPTION 'Deal assignment required' USING ERRCODE='42501'; END IF;
  IF d.stage IS DISTINCT FROM next_stage THEN
    UPDATE public.crm_deals SET stage=next_stage WHERE id=p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id,action,from_status,to_status,actor_id)
      VALUES(p_deal_id,'STAGE_CHANGED',d.stage,next_stage,auth.uid());
  END IF;
  IF next_stage='QUALIFICATION' THEN task_id := public.create_crm_contact_discussion_task(p_deal_id); END IF;
  RETURN jsonb_build_object('deal_id',p_deal_id,'from_stage',d.stage,'to_stage',next_stage,'task_id',task_id,'actor_id',auth.uid());
END $body$;

CREATE FUNCTION public.start_crm_quote_proposal(p_deal_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
DECLARE d public.crm_deals%ROWTYPE; task_id uuid; already_registered boolean; list_id uuid; designer_id uuid; n integer;
BEGIN
  IF auth.uid() IS NULL OR NOT coalesce(public.can_access_crm(auth.uid()),false)
    OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO d FROM public.crm_deals WHERE id=p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE='P0002'; END IF;
  IF auth.uid() IS DISTINCT FROM d.created_by AND auth.uid() IS DISTINCT FROM d.assigned_to
      AND NOT auth.uid()=ANY(coalesce(d.assignee_ids,'{}'::uuid[])) THEN
    RAISE EXCEPTION 'Deal assignment required' USING ERRCODE='42501'; END IF;
  IF d.stage<>'DISCUSSION' THEN RAISE EXCEPTION 'Deal must be in Discussion' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id=p_deal_id AND category='QUOTATION' AND is_archived=false AND nullif(btrim(file_url),'') IS NOT NULL)
     OR NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id=p_deal_id AND category='PROPOSAL' AND is_archived=false AND nullif(btrim(file_url),'') IS NOT NULL AND nullif(btrim(description),'') IS NOT NULL AND file_type LIKE 'image/%') THEN
    RAISE EXCEPTION 'Quote and described proposal image are required' USING ERRCODE='23514'; END IF;
  IF EXISTS (SELECT 1 FROM public.crm_generated_tasks WHERE deal_id=p_deal_id AND kind='QUOTE_PROPOSAL_DESIGN') THEN
    RAISE EXCEPTION 'Historical Design mapping requires review' USING ERRCODE='23514'; END IF;
  SELECT count(*) INTO n FROM public.task_lists WHERE coalesce(name,'') ~* '(design|تصميم)';
  IF n<>1 THEN RAISE EXCEPTION 'Configure exactly one Design task list' USING ERRCODE='23514'; END IF;
  SELECT id INTO list_id FROM public.task_lists WHERE coalesce(name,'') ~* '(design|تصميم)';
  SELECT count(*) INTO n FROM public.profiles WHERE emp_index=8 AND is_active IS DISTINCT FROM false;
  IF n<>1 THEN RAISE EXCEPTION 'Configure exactly one active MQ-08 employee' USING ERRCODE='23514'; END IF;
  SELECT id INTO designer_id FROM public.profiles WHERE emp_index=8 AND is_active IS DISTINCT FROM false;
  IF NOT EXISTS (SELECT 1 FROM public.task_lists l JOIN public.profiles p ON p.id=designer_id JOIN public.departments department ON department.id=l.department_id
    WHERE l.id=list_id AND p.department_id=l.department_id AND department.is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'Design list and designer department mismatch' USING ERRCODE='23514'; END IF;
  SELECT EXISTS(SELECT 1 FROM public.crm_generated_tasks WHERE deal_id=p_deal_id AND kind='QUOTE_PROPOSAL') INTO already_registered;
  INSERT INTO hrsys_private.crm_quote_proposal_context(backend_pid,transaction_id,actor_id,deal_id,list_id,designer_id)
    VALUES(pg_backend_pid(),txid_current(),auth.uid(),p_deal_id,list_id,designer_id);
  task_id := public.ensure_crm_generated_task(p_deal_id,'QUOTE_PROPOSAL');
  DELETE FROM hrsys_private.crm_quote_proposal_context WHERE backend_pid=pg_backend_pid() AND transaction_id=txid_current();
  IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE id=task_id AND crm_deal_id=p_deal_id AND crm_workflow_kind='QUOTE_PROPOSAL' AND archived_at IS NULL) THEN
    RAISE EXCEPTION 'Generated task identity mismatch' USING ERRCODE='23514'; END IF;
  UPDATE public.crm_deals SET design_task_id=task_id,approval_type='QUOTE_PROPOSAL',workflow_status='DESIGN_IN_PROGRESS',proposal_sent_at=coalesce(proposal_sent_at,now()) WHERE id=p_deal_id;
  IF NOT already_registered THEN
    INSERT INTO public.crm_deal_activity(deal_id,action,note,actor_id) VALUES(p_deal_id,'QUOTE_PROPOSAL_STARTED',task_id::text,auth.uid());
  END IF;
  RETURN task_id;
END $body$;
ALTER FUNCTION public.start_crm_quote_proposal(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.start_crm_quote_proposal(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.start_crm_quote_proposal(uuid) TO authenticated,service_role;
CREATE FUNCTION public.submit_crm_quote_proposal_files(p_task_id uuid,p_links text[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
DECLARE task_row public.tasks%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'Active user required' USING ERRCODE='42501'; END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id=p_task_id FOR UPDATE;
  IF NOT FOUND OR task_row.crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL' OR task_row.archived_at IS NOT NULL
     OR lower(btrim(coalesce(task_row.status,'')))='completed'
     OR NOT EXISTS (SELECT 1 FROM public.crm_generated_tasks WHERE task_id=p_task_id AND deal_id=task_row.crm_deal_id AND kind='QUOTE_PROPOSAL')
     OR NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id=task_row.crm_deal_id AND stage='DISCUSSION')
     OR (auth.uid() IS DISTINCT FROM task_row.assignee_id AND NOT auth.uid()=ANY(coalesce(task_row.assignee_ids,'{}'::uuid[]))) THEN
    RAISE EXCEPTION 'Assigned Quote & Proposal task required' USING ERRCODE='42501'; END IF;
  IF p_links IS NULL OR EXISTS (SELECT 1 FROM unnest(p_links) link WHERE NOT EXISTS (
     SELECT 1 FROM public.task_attachments attachment WHERE attachment.task_id=p_task_id AND attachment.file_url=link
       AND attachment.is_archived=false AND (attachment.file_type='application/pdf' OR attachment.file_type LIKE 'image/%'))) THEN
    RAISE EXCEPTION 'Registered Design PDF or image required' USING ERRCODE='23514'; END IF;
  UPDATE public.tasks SET submission_links=p_links,upload_link=p_links[1] WHERE id=p_task_id;
END $body$;
ALTER FUNCTION public.submit_crm_quote_proposal_files(uuid,text[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.submit_crm_quote_proposal_files(uuid,text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.submit_crm_quote_proposal_files(uuid,text[]) TO authenticated,service_role;
-- Historical approval rows remain readable; stop starting or deciding new
-- CRM approval cycles through the old authenticated entry points.
REVOKE EXECUTE ON FUNCTION public.start_deal_approval(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.start_crm_presentation_approval(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.decide_deal_approval(uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.decide_crm_design_task_approval(uuid,text,text) FROM PUBLIC,anon,authenticated;
DO $post$ BEGIN
  IF has_function_privilege('anon','public.start_crm_quote_proposal(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.start_crm_quote_proposal(uuid)','EXECUTE')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.start_crm_quote_proposal(uuid)'::regprocedure AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp']) THEN
    RAISE EXCEPTION 'Quote & Proposal security postcondition mismatch';
  END IF;
  IF has_function_privilege('anon','public.submit_crm_quote_proposal_files(uuid,text[])','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.submit_crm_quote_proposal_files(uuid,text[])','EXECUTE')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.submit_crm_quote_proposal_files(uuid,text[])'::regprocedure AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp'])
     OR has_table_privilege('authenticated','hrsys_private.crm_quote_proposal_context','INSERT')
     OR has_table_privilege('anon','hrsys_private.crm_quote_proposal_context','INSERT')
     OR has_function_privilege('authenticated','hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','hrsys_private.can_read_quote_proposal_source(uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','hrsys_private.can_read_quote_proposal_source(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[])','EXECUTE')
     OR has_function_privilege('anon','hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[])','EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc WHERE oid IN ('hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)'::regprocedure,'hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[])'::regprocedure,'hrsys_private.can_read_quote_proposal_source(uuid,uuid)'::regprocedure)
       AND (proowner<>'postgres'::regrole OR NOT prosecdef OR proconfig<>ARRAY['search_path=public, pg_temp']))
     OR has_table_privilege('authenticated','public.projects','SELECT') THEN
    RAISE EXCEPTION 'Submission or project security postcondition mismatch';
  END IF;
  IF has_function_privilege('authenticated','public.start_deal_approval(uuid,uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.start_crm_presentation_approval(uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.decide_deal_approval(uuid,text,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.decide_crm_design_task_approval(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Obsolete CRM approval entry point remains executable';
  END IF;
END $post$;
COMMIT;
