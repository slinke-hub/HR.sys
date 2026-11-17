\set ON_ERROR_STOP on
GRANT USAGE ON SCHEMA auth TO authenticated;
INSERT INTO auth.users(id) SELECT id FROM (VALUES
 ('a0000000-0000-4000-8000-000000000101'::uuid),('a0000000-0000-4000-8000-000000000001'::uuid),
 ('a0000000-0000-4000-8000-000000000003'::uuid),('a0000000-0000-4000-8000-000000000004'::uuid),('a0000000-0000-4000-8000-000000000008'::uuid)) v(id);
INSERT INTO public.departments(id,name) VALUES ('b0000000-0000-4000-8000-000000000001','Synthetic Sales'),('b0000000-0000-4000-8000-000000000002','Design');
INSERT INTO public.profiles(id,full_name,department_id,role,is_active,task_email_notifications,employee_id,emp_index) VALUES
 ('a0000000-0000-4000-8000-000000000101','Synthetic CRM','b0000000-0000-4000-8000-000000000001','EMPLOYEE',true,false,NULL,101),
 ('a0000000-0000-4000-8000-000000000001','Synthetic GM','b0000000-0000-4000-8000-000000000002','EMPLOYEE',true,false,'MQ-01',1),
 ('a0000000-0000-4000-8000-000000000003','Synthetic Marketing','b0000000-0000-4000-8000-000000000001','EMPLOYEE',true,false,'MQ-03',3),
 ('a0000000-0000-4000-8000-000000000004','Synthetic Operations','b0000000-0000-4000-8000-000000000002','EMPLOYEE',true,false,'MQ-04',4),
 ('a0000000-0000-4000-8000-000000000008','Synthetic Designer','b0000000-0000-4000-8000-000000000002','EMPLOYEE',true,false,'MQ-08',8);
INSERT INTO public.task_lists(id,owner_id,name,department_id) VALUES ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000008','Design','b0000000-0000-4000-8000-000000000002');
INSERT INTO public.crm_clients(id,name) VALUES ('d0000000-0000-4000-8000-000000000001','Synthetic Client');
INSERT INTO public.crm_deals(id,title,client_id,stage,workflow_status,approval_type,first_contact_date,contact_method,created_by,assigned_to) VALUES
 ('e0000000-0000-4000-8000-000000000001','Synthetic Design approval','d0000000-0000-4000-8000-000000000001','LEAD','NOT_STARTED','QUOTE_PROPOSAL','2026-11-01','PHONE','a0000000-0000-4000-8000-000000000101','a0000000-0000-4000-8000-000000000101');
INSERT INTO public.crm_deal_attachments(deal_id,category,file_name,file_url) VALUES
 ('e0000000-0000-4000-8000-000000000001','QUOTATION','synthetic.txt','storage://crm-deal-files/synthetic/quote'),
 ('e0000000-0000-4000-8000-000000000001','PROPOSAL','synthetic.txt','storage://crm-deal-files/synthetic/proposal');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',false);
SELECT public.start_deal_approval('e0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000004');
RESET ROLE;
SELECT set_config('test.m',(SELECT id::text FROM public.crm_deal_approval_steps WHERE deal_id='e0000000-0000-4000-8000-000000000001' AND stage_key='MARKETING_MANAGER'),false);
SELECT set_config('test.g',(SELECT id::text FROM public.crm_deal_approval_steps WHERE deal_id='e0000000-0000-4000-8000-000000000001' AND stage_key='GENERAL_MANAGER'),false);
SELECT set_config('test.o',(SELECT id::text FROM public.crm_deal_approval_steps WHERE deal_id='e0000000-0000-4000-8000-000000000001' AND stage_key='OPERATIONS_MANAGER'),false);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',false);
SELECT public.decide_deal_approval(current_setting('test.m')::uuid,'APPROVED',NULL);
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',false);
SELECT public.decide_deal_approval(current_setting('test.g')::uuid,'APPROVED',NULL);
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000004',false);
SELECT public.decide_deal_approval(current_setting('test.o')::uuid,'APPROVED',NULL);
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE crm_deal_id='e0000000-0000-4000-8000-000000000001' AND crm_workflow_kind='QUOTE_PROPOSAL_DESIGN') THEN RAISE EXCEPTION 'Design task missing after approval'; END IF;
 IF (SELECT count(*) FROM public.tasks t JOIN public.crm_generated_tasks m ON m.task_id=t.id AND m.deal_id=t.crm_deal_id AND m.kind=t.crm_workflow_kind WHERE t.crm_deal_id='e0000000-0000-4000-8000-000000000001' AND t.crm_workflow_kind='QUOTE_PROPOSAL_DESIGN') <> 1 THEN RAISE EXCEPTION 'Design task registry mapping missing or duplicated'; END IF;
END $$;
-- An unregistered generated identity must be rejected even when table-owner
-- privileges bypass ordinary task RLS. The protection itself must fire.
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN
  INSERT INTO public.tasks(id,title,created_by,assignee_id,status,department,sub_type,crm_deal_id,crm_workflow_kind)
  VALUES ('f0000000-0000-4000-8000-000000000001','Synthetic forged Design',
    'a0000000-0000-4000-8000-000000000101','a0000000-0000-4000-8000-000000000008',
    'todo','Design','Designing Task','e0000000-0000-4000-8000-000000000001','QUOTE_PROPOSAL_DESIGN');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unregistered Design insertion accepted'; END IF;
END $$;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000004',false);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.decide_deal_approval(current_setting('test.o')::uuid,'APPROVED',NULL);
 EXCEPTION WHEN raise_exception OR insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Repeated Design approval accepted'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.tasks WHERE crm_deal_id='e0000000-0000-4000-8000-000000000001' AND crm_workflow_kind='QUOTE_PROPOSAL_DESIGN')<>1 THEN RAISE EXCEPTION 'Design retry duplicated task'; END IF;
END $$;
-- Existing Marketing Design review must still work after the compatibility patch.
INSERT INTO public.departments(id,name,head_id) VALUES ('b0000000-0000-4000-8000-000000000003','Marketing','a0000000-0000-4000-8000-000000000003');
UPDATE public.departments SET head_id='a0000000-0000-4000-8000-000000000003' WHERE id='b0000000-0000-4000-8000-000000000001';
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',false);
INSERT INTO public.tasks(id,title,created_by,assignee_id,status,department,sub_type)
VALUES ('f0000000-0000-4000-8000-000000000002','Synthetic marketing design',
 'a0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000008','todo','Marketing','Designing Task');
DO $$ BEGIN
 IF (SELECT status FROM public.tasks WHERE id='f0000000-0000-4000-8000-000000000002') <> 'review' THEN RAISE EXCEPTION 'Marketing Design did not enter review'; END IF;
END $$;
UPDATE public.tasks SET delivery_status='Approved' WHERE id='f0000000-0000-4000-8000-000000000002';
DO $$ BEGIN
 IF (SELECT status FROM public.tasks WHERE id='f0000000-0000-4000-8000-000000000002') <> 'completed' THEN RAISE EXCEPTION 'Marketing Design approval did not complete'; END IF;
END $$;
SELECT 'DESIGN_APPROVAL_WORKFLOW=PASS';
