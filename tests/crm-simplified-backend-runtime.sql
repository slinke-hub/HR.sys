\set ON_ERROR_STOP on
BEGIN;
GRANT USAGE ON SCHEMA auth TO authenticated;
INSERT INTO auth.users(id) VALUES
 ('a0000000-0000-4000-8000-000000000101'),('a0000000-0000-4000-8000-000000000008'),('a0000000-0000-4000-8000-000000000102'),('a0000000-0000-4000-8000-000000000103');
INSERT INTO public.departments(id,name) VALUES
 ('b0000000-0000-4000-8000-000000000001','Synthetic Sales'),('b0000000-0000-4000-8000-000000000002','Synthetic Marketing Design'),('b0000000-0000-4000-8000-000000000003','Synthetic Other');
INSERT INTO public.profiles(id,full_name,department_id,role,is_active,task_email_notifications,employee_id,emp_index) VALUES
 ('a0000000-0000-4000-8000-000000000101','Synthetic Sales','b0000000-0000-4000-8000-000000000002','EMPLOYEE',true,false,'MQ-20',101),
 ('a0000000-0000-4000-8000-000000000008','Synthetic Designer','b0000000-0000-4000-8000-000000000002','EMPLOYEE',true,false,'MQ-08',8),
 ('a0000000-0000-4000-8000-000000000102','Synthetic Other','b0000000-0000-4000-8000-000000000003','EMPLOYEE',true,false,NULL,102),
 ('a0000000-0000-4000-8000-000000000103','Synthetic Unassigned Sales','b0000000-0000-4000-8000-000000000001','EMPLOYEE',true,false,NULL,103);
INSERT INTO public.task_lists(id,owner_id,name,department_id,can_add_users) VALUES
 ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','Design','b0000000-0000-4000-8000-000000000002','{}'::uuid[]);
INSERT INTO public.crm_clients(id,name) VALUES ('d0000000-0000-4000-8000-000000000001','Synthetic client');
INSERT INTO public.crm_deals(id,title,client_id,stage,workflow_status,first_contact_date,contact_method,created_by,assigned_to) VALUES
 ('e0000000-0000-4000-8000-000000000001','Synthetic simplified','d0000000-0000-4000-8000-000000000001','LEAD','NOT_STARTED','2026-11-01','PHONE','a0000000-0000-4000-8000-000000000101','a0000000-0000-4000-8000-000000000101');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',true);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.start_crm_quote_proposal('e0000000-0000-4000-8000-000000000001'); EXCEPTION WHEN check_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Quote & Proposal started outside Discussion'; END IF;
END $$;
SELECT public.change_crm_deal_stage('e0000000-0000-4000-8000-000000000001','QUALIFICATION');
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.change_crm_deal_stage('e0000000-0000-4000-8000-000000000001','NEGOTIATION'); EXCEPTION WHEN check_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Qualification skipped Discussion'; END IF;
END $$;
SELECT public.change_crm_deal_stage('e0000000-0000-4000-8000-000000000001','DISCUSSION');
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000103',true);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.change_crm_deal_stage('e0000000-0000-4000-8000-000000000001','NEGOTIATION'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unassigned CRM user changed stage'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',true);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN INSERT INTO public.tasks(id,title,created_by,assignee_id,crm_deal_id,crm_workflow_kind)
 VALUES ('f0000000-0000-4000-8000-000000000010','Synthetic forged task','a0000000-0000-4000-8000-000000000101','a0000000-0000-4000-8000-000000000008','e0000000-0000-4000-8000-000000000001','QUOTE_PROPOSAL');
 EXCEPTION WHEN insufficient_privilege OR check_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Direct generated-task insert succeeded'; END IF;
 denied:=false;
 BEGIN PERFORM public.change_crm_deal_stage('e0000000-0000-4000-8000-000000000001','NEGOTIATION'); EXCEPTION WHEN check_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Negotiation bypassed Quote & Proposal'; END IF;
 denied:=false;
 BEGIN UPDATE public.crm_deals SET stage='NEGOTIATION' WHERE id='e0000000-0000-4000-8000-000000000001'; EXCEPTION WHEN check_violation OR insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Direct update bypassed Quote & Proposal'; END IF;
END $$;
RESET ROLE;
INSERT INTO public.crm_deal_attachments(deal_id,category,file_name,file_url,file_type,description) VALUES
 ('e0000000-0000-4000-8000-000000000001','QUOTATION','synthetic.pdf','storage://crm-deal-files/synthetic/quote','application/pdf','synthetic'),
 ('e0000000-0000-4000-8000-000000000001','PROPOSAL','synthetic.png','storage://crm-deal-files/synthetic/proposal','image/png','synthetic');
UPDATE public.departments SET is_active=false WHERE id='b0000000-0000-4000-8000-000000000002';
SET ROLE authenticated;
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.start_crm_quote_proposal('e0000000-0000-4000-8000-000000000001'); EXCEPTION WHEN insufficient_privilege OR check_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Inactive Design department accepted'; END IF;
END $$;
RESET ROLE;
UPDATE public.departments SET is_active=true WHERE id='b0000000-0000-4000-8000-000000000002';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',true);
SELECT public.start_crm_quote_proposal('e0000000-0000-4000-8000-000000000001');
SELECT public.start_crm_quote_proposal('e0000000-0000-4000-8000-000000000001');
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.crm_generated_tasks WHERE deal_id='e0000000-0000-4000-8000-000000000001' AND kind='QUOTE_PROPOSAL')<>1 THEN RAISE EXCEPTION 'Registry count mismatch'; END IF;
 IF (SELECT count(*) FROM public.tasks WHERE crm_deal_id='e0000000-0000-4000-8000-000000000001' AND crm_workflow_kind='QUOTE_PROPOSAL')<>1 THEN RAISE EXCEPTION 'Task count mismatch'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE crm_deal_id='e0000000-0000-4000-8000-000000000001' AND crm_workflow_kind='QUOTE_PROPOSAL' AND assignee_id='a0000000-0000-4000-8000-000000000008' AND task_list_id='c0000000-0000-4000-8000-000000000001' AND created_by='a0000000-0000-4000-8000-000000000101') THEN RAISE EXCEPTION 'Design routing mismatch'; END IF;
 IF has_table_privilege('authenticated','public.projects','SELECT') THEN RAISE EXCEPTION 'Broad projects SELECT'; END IF;
END $$;
SELECT set_config('test.simplified_task',(SELECT task_id::text FROM public.crm_generated_tasks WHERE deal_id='e0000000-0000-4000-8000-000000000001' AND kind='QUOTE_PROPOSAL'),true);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000102',true);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.start_crm_quote_proposal('e0000000-0000-4000-8000-000000000001'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unauthorized user started workflow'; END IF;
 denied:=false;
 BEGIN PERFORM public.submit_crm_quote_proposal_files(current_setting('test.simplified_task')::uuid,ARRAY['storage://task-attachments/synthetic/design.png']); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unauthorized user submitted Design files'; END IF;
 denied:=false;
 BEGIN PERFORM public.change_task_status(current_setting('test.simplified_task')::uuid,'completed'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unauthorized user completed Design task'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000008',true);
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.list_accessible_tasks_secure() item WHERE item->>'id'=current_setting('test.simplified_task')) THEN RAISE EXCEPTION 'Design assignee cannot list generated task'; END IF;
END $$;
SELECT public.add_task_comment(current_setting('test.simplified_task')::uuid,'Synthetic Design comment','[]'::jsonb);
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.list_task_comments_secure(current_setting('test.simplified_task')::uuid) WHERE content='Synthetic Design comment') THEN RAISE EXCEPTION 'Design comment missing'; END IF;
END $$;
SELECT public.register_task_attachment(current_setting('test.simplified_task')::uuid,'storage://task-attachments/synthetic/design.png','design.png','image/png',8,'TASK',false);
SELECT public.submit_crm_quote_proposal_files(current_setting('test.simplified_task')::uuid,ARRAY['storage://task-attachments/synthetic/design.png']);
SELECT public.change_task_status(current_setting('test.simplified_task')::uuid,'completed');
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',true);
SELECT public.change_crm_deal_stage('e0000000-0000-4000-8000-000000000001','NEGOTIATION');
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN UPDATE public.crm_deals SET stage='WON' WHERE id='e0000000-0000-4000-8000-000000000001'; EXCEPTION WHEN check_violation OR insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Direct Won update bypassed the order workflow'; END IF;
END $$;
SAVEPOINT before_won;
DO $$ DECLARE denied boolean:=false; BEGIN
 IF public.can_view_business_financials(auth.uid()) THEN RAISE EXCEPTION 'Financial negative-test actor is financially authorized'; END IF;
 BEGIN PERFORM public.create_project_from_won_deal_v2('e0000000-0000-4000-8000-000000000001',
   '{"project_amount":"999","event_date":"2026-12-01","event_start_time":"10:00","client":{"name":"Synthetic client"},"installation_type":"INDOOR","assigned_people":["a0000000-0000-4000-8000-000000000101"]}'::jsonb);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Nonfinancial user could set project amount'; END IF;
END $$;
SELECT public.create_project_from_won_deal_v2('e0000000-0000-4000-8000-000000000001',
  '{"event_date":"2026-12-01","event_start_time":"10:00","client":{"name":"Synthetic client"},"installation_type":"INDOOR","assigned_people":["a0000000-0000-4000-8000-000000000101"]}'::jsonb);
DO $$ BEGIN IF (SELECT stage FROM public.crm_deals WHERE id='e0000000-0000-4000-8000-000000000001')<>'WON' THEN RAISE EXCEPTION 'Won transition failed'; END IF; END $$;
ROLLBACK TO before_won;
SELECT public.mark_crm_deal_lost('e0000000-0000-4000-8000-000000000001','Synthetic reason');
RESET ROLE;
DO $$ BEGIN
 IF (SELECT stage FROM public.crm_deals WHERE id='e0000000-0000-4000-8000-000000000001')<>'LOST' THEN RAISE EXCEPTION 'Lost transition failed'; END IF;
END $$;
ROLLBACK;
SELECT 'SIMPLIFIED_BACKEND_RUNTIME=PASS';
