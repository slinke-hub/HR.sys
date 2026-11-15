\set ON_ERROR_STOP on
INSERT INTO public.crm_design_task_approval_steps(id,task_id,deal_id,step_order,stage_key,approver_id,status)
SELECT 'f1000000-0000-4000-8000-000000000001',id,crm_deal_id,1,'GENERAL_MANAGER','a0000000-0000-4000-8000-000000000101','PENDING'
FROM public.tasks WHERE crm_deal_id='e0000000-0000-4000-8000-000000000001' AND crm_workflow_kind='QUOTE_PROPOSAL_DESIGN';
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',false);
INSERT INTO public.task_attachments(task_id,user_id,file_name,file_url,file_type,is_archived)
SELECT id,'a0000000-0000-4000-8000-000000000101','synthetic.pdf','storage://task-attachments/synthetic/design-terminal.pdf','application/pdf',false
FROM public.tasks WHERE crm_deal_id='e0000000-0000-4000-8000-000000000001' AND crm_workflow_kind='QUOTE_PROPOSAL_DESIGN';
UPDATE public.tasks SET submission_links=ARRAY['storage://task-attachments/synthetic/design-terminal.pdf'] WHERE crm_deal_id='e0000000-0000-4000-8000-000000000001' AND crm_workflow_kind='QUOTE_PROPOSAL_DESIGN';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',false);
SELECT public.mark_crm_deal_lost('e0000000-0000-4000-8000-000000000001','Synthetic terminal test');
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',false);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.decide_crm_design_task_approval('f1000000-0000-4000-8000-000000000001','APPROVED',NULL);
 EXCEPTION WHEN raise_exception OR insufficient_privilege OR check_violation THEN denied:=true; PERFORM set_config('test.design_terminal_error',SQLERRM,false); END;
 IF NOT denied THEN RAISE EXCEPTION 'Design decision accepted after Lost'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.crm_deals WHERE id='e0000000-0000-4000-8000-000000000001' AND stage='LOST') THEN RAISE EXCEPTION 'Design approval changed Lost deal'; END IF; END $$;
SELECT 'DESIGN_LOST_TERMINAL=PASS: ' || current_setting('test.design_terminal_error');
UPDATE public.crm_deals SET stage='WON',workflow_status='APPROVED',lost_reason=NULL WHERE id='e0000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000101',false);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.decide_crm_design_task_approval('f1000000-0000-4000-8000-000000000001','APPROVED',NULL);
 EXCEPTION WHEN raise_exception OR insufficient_privilege OR check_violation THEN denied:=true; PERFORM set_config('test.design_won_error',SQLERRM,false); END;
 IF NOT denied THEN RAISE EXCEPTION 'Design decision accepted after Won'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.crm_deals WHERE id='e0000000-0000-4000-8000-000000000001' AND stage='WON') THEN RAISE EXCEPTION 'Design approval changed Won deal'; END IF; END $$;
SELECT 'DESIGN_WON_TERMINAL=PASS: ' || current_setting('test.design_won_error');
