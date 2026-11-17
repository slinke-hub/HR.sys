\set ON_ERROR_STOP on
BEGIN;
-- The concurrency fixture's Sales and Design users are synthetic. Move Sales
-- temporarily to its own department, retaining the original Design list.
UPDATE public.profiles SET department_id='b0000000-0000-4000-8000-000000000001'
 WHERE id='a0000000-0000-4000-8000-000000000101';
INSERT INTO public.crm_deals(id,title,client_id,stage,workflow_status,first_contact_date,contact_method,created_by,assigned_to)
 VALUES ('e0000000-0000-4000-8000-000000000002','Synthetic cross-department','d0000000-0000-4000-8000-000000000001',
 'LEAD','NOT_STARTED','2026-11-01','PHONE','a0000000-0000-4000-8000-000000000101','a0000000-0000-4000-8000-000000000101');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',true);
SELECT public.change_crm_deal_stage('e0000000-0000-4000-8000-000000000002','QUALIFICATION');
SELECT public.change_crm_deal_stage('e0000000-0000-4000-8000-000000000002','DISCUSSION');
RESET ROLE;
INSERT INTO public.crm_deal_attachments(deal_id,category,file_name,file_url,file_type,description) VALUES
 ('e0000000-0000-4000-8000-000000000002','QUOTATION','quote.pdf','storage://crm-deal-files/synthetic/cross/q','application/pdf','synthetic'),
 ('e0000000-0000-4000-8000-000000000002','PROPOSAL','proposal.png','storage://crm-deal-files/synthetic/cross/p','image/png','synthetic'),
 ('e0000000-0000-4000-8000-000000000002','CLIENT_IDENTITY','identity.pdf','storage://crm-deal-files/synthetic/cross/i','application/pdf','synthetic');
SET ROLE authenticated;
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN INSERT INTO hrsys_private.crm_quote_proposal_context(backend_pid,transaction_id,actor_id,deal_id,list_id,designer_id)
 VALUES (pg_backend_pid(),txid_current(),auth.uid(),'e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'User forged routing context'; END IF;
 denied:=false;
 BEGIN PERFORM hrsys_private.valid_crm_quote_proposal_context('e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000001',NULL);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'User accessed private routing helper'; END IF;
 denied:=false;
 BEGIN INSERT INTO public.tasks(id,title,created_by,assignee_id,task_list_id)
 VALUES ('f0000000-0000-4000-8000-000000000090','Synthetic ordinary task','a0000000-0000-4000-8000-000000000101','a0000000-0000-4000-8000-000000000008','c0000000-0000-4000-8000-000000000001');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Ordinary cross-department task unexpectedly allowed'; END IF;
END $$;
SELECT public.start_crm_quote_proposal('e0000000-0000-4000-8000-000000000002');
SELECT public.start_crm_quote_proposal('e0000000-0000-4000-8000-000000000002');
RESET ROLE;
SELECT set_config('test.cross_design_task',(SELECT task_id::text FROM public.crm_generated_tasks WHERE deal_id='e0000000-0000-4000-8000-000000000002' AND kind='QUOTE_PROPOSAL'),true);
SET ROLE authenticated;
DO $$ DECLARE denied boolean:=false; BEGIN
 IF public.can_add_task_to_list('c0000000-0000-4000-8000-000000000001',auth.uid())
    OR public.can_access_task(current_setting('test.cross_design_task')::uuid,auth.uid())
    OR public.can_view_task(current_setting('test.cross_design_task')::uuid,auth.uid())
    OR public.can_manage_task(current_setting('test.cross_design_task')::uuid,auth.uid())
    OR public.can_delete_task(current_setting('test.cross_design_task')::uuid,auth.uid())
    OR public.can_manage_task_attachments(current_setting('test.cross_design_task')::uuid,auth.uid())
    OR EXISTS (SELECT 1 FROM public.tasks WHERE id=current_setting('test.cross_design_task')::uuid) THEN
   RAISE EXCEPTION 'Sales initiator gained unrestricted Design access'; END IF;
 BEGIN PERFORM public.change_task_status(current_setting('test.cross_design_task')::uuid,'completed'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Sales initiator changed Design task status'; END IF;
 denied:=false;
 BEGIN PERFORM public.delete_task_secure(current_setting('test.cross_design_task')::uuid); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Sales initiator deleted Design task'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF public.can_execute_task(current_setting('test.cross_design_task')::uuid,auth.uid()) OR public.task_belongs_to_employee(current_setting('test.cross_design_task')::uuid,auth.uid()) THEN
   RAISE EXCEPTION 'Sales initiator has creator-only execution or employee-grant access'; END IF;
END $$;
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN INSERT INTO public.tasks(id,title,created_by,assignee_id,task_list_id)
 VALUES ('f0000000-0000-4000-8000-000000000091','Synthetic trigger-only probe','a0000000-0000-4000-8000-000000000101','a0000000-0000-4000-8000-000000000008','c0000000-0000-4000-8000-000000000001');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'List trigger accepted ordinary cross-department insert'; END IF;
END $$;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.crm_generated_tasks WHERE deal_id='e0000000-0000-4000-8000-000000000002' AND kind='QUOTE_PROPOSAL') <> 1 THEN RAISE EXCEPTION 'Registry count mismatch'; END IF;
 IF (SELECT count(*) FROM public.tasks WHERE crm_deal_id='e0000000-0000-4000-8000-000000000002' AND crm_workflow_kind='QUOTE_PROPOSAL' AND assignee_id='a0000000-0000-4000-8000-000000000008' AND task_list_id='c0000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'Design routing mismatch'; END IF;
 IF EXISTS (SELECT 1 FROM hrsys_private.crm_quote_proposal_context) THEN RAISE EXCEPTION 'Context leaked'; END IF;
 IF has_table_privilege('authenticated','hrsys_private.crm_quote_proposal_context','INSERT') OR has_function_privilege('authenticated','hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Context is exposed'; END IF;
END $$;
-- Diagnose a non-CRM Design employee without exposing file contents.
UPDATE public.departments SET name='Synthetic Design' WHERE id='b0000000-0000-4000-8000-000000000002';
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000008',true);
DO $$ BEGIN
 IF public.can_access_crm(auth.uid()) THEN RAISE EXCEPTION 'Synthetic designer unexpectedly has CRM access'; END IF;
 IF NOT public.can_read_crm_deal_file('synthetic/cross/p',auth.uid()) OR NOT public.can_read_crm_deal_file('synthetic/cross/q',auth.uid()) THEN RAISE EXCEPTION 'Assigned designer cannot read sources'; END IF;
 IF public.can_read_crm_deal_file('synthetic/cross/i',auth.uid()) THEN RAISE EXCEPTION 'Unapproved file category accessible'; END IF;
 IF (SELECT count(*) FROM public.list_crm_deal_attachments_secure('e0000000-0000-4000-8000-000000000002'))<>2 THEN RAISE EXCEPTION 'Scoped metadata mismatch'; END IF;
 IF public.can_read_crm_deal_file('synthetic/cross/p','a0000000-0000-4000-8000-000000000102') THEN RAISE EXCEPTION 'Arbitrary-user authorization probe allowed'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','',true);
INSERT INTO auth.users(id) VALUES ('a0000000-0000-4000-8000-000000000104');
INSERT INTO public.profiles(id,full_name,department_id,role,is_active,task_email_notifications,emp_index) VALUES
 ('a0000000-0000-4000-8000-000000000104','Synthetic replacement designer','b0000000-0000-4000-8000-000000000002','EMPLOYEE',true,false,104);
SELECT set_config('test.cross_design_task',(SELECT task_id::text FROM public.crm_generated_tasks WHERE deal_id='e0000000-0000-4000-8000-000000000002' AND kind='QUOTE_PROPOSAL'),true);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',true);
SELECT public.assign_task(current_setting('test.cross_design_task')::uuid, ARRAY['a0000000-0000-4000-8000-000000000104'::uuid]);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.assign_task(current_setting('test.cross_design_task')::uuid, ARRAY['a0000000-0000-4000-8000-000000000102'::uuid]);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Assignment outside the Design department was allowed'; END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000008',true);
DO $$ BEGIN
 IF public.can_read_crm_deal_file('synthetic/cross/p',auth.uid()) THEN RAISE EXCEPTION 'Removed designer retained source access'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000104',true);
DO $$ BEGIN
 IF NOT public.can_read_crm_deal_file('synthetic/cross/p',auth.uid()) OR (SELECT count(*) FROM public.list_crm_deal_attachments_secure('e0000000-0000-4000-8000-000000000002'))<>2 THEN RAISE EXCEPTION 'New designer lacks source access'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000102',true);
DO $$ BEGIN
 IF public.can_read_crm_deal_file('synthetic/cross/p',auth.uid()) OR EXISTS (SELECT 1 FROM public.list_crm_deal_attachments_secure('e0000000-0000-4000-8000-000000000002')) THEN RAISE EXCEPTION 'Unassigned user read source'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','',true);
UPDATE public.tasks SET archived_at=now()
 WHERE id=(SELECT task_id FROM public.crm_generated_tasks WHERE deal_id='e0000000-0000-4000-8000-000000000002' AND kind='QUOTE_PROPOSAL');
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000008',true);
DO $$ BEGIN
 IF public.can_read_crm_deal_file('synthetic/cross/p',auth.uid()) OR EXISTS (SELECT 1 FROM public.list_crm_deal_attachments_secure('e0000000-0000-4000-8000-000000000002')) THEN RAISE EXCEPTION 'Archived task retained source access'; END IF;
END $$;
ROLLBACK;
SELECT 'CROSS_DEPARTMENT_ROUTING_AND_SOURCE_SECURITY=PASS';
