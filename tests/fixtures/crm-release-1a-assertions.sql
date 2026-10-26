CREATE FUNCTION test_assert(ok boolean, label text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %', label; END IF; RETURN 'PASS: ' || label; END $$;
CREATE FUNCTION test_denied(statement text, expected_state text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = expected_state THEN RETURN 'PASS: denied ' || statement; END IF;
    RAISE;
  END;
  RAISE EXCEPTION 'FAIL: expected SQLSTATE % for %', expected_state, statement;
END $$;
SELECT test_assert((SELECT count(*) = 1 FROM pg_trigger
 WHERE tgrelid='public.crm_deals'::regclass AND tgfoid='public.enforce_deal_workflow_transition()'::regprocedure
 AND NOT tgisinternal AND tgenabled='O'), 'Exactly one enabled CRM workflow trigger remains');
SELECT test_assert((SELECT pg_get_triggerdef(oid) ILIKE '%UPDATE OF stage, workflow_status, lost_reason%'
 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgfoid='public.enforce_deal_workflow_transition()'::regprocedure
 AND NOT tgisinternal), 'CRM trigger covers stage, workflow_status, and lost_reason');
SELECT test_assert(NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass
 AND tgname='crm_deals_enforce_workflow_transition' AND NOT tgisinternal), 'Legacy CRM workflow trigger was removed');
SELECT test_assert(NOT has_function_privilege('anon','public.can_add_task_to_list(uuid,uuid)','EXECUTE')
 AND has_function_privilege('authenticated','public.can_add_task_to_list(uuid,uuid)','EXECUTE')
 AND NOT EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid='public.can_add_task_to_list(uuid,uuid)'::regprocedure AND a.grantee=0 AND a.privilege_type='EXECUTE'),
 'Task-list helper denies anon and PUBLIC while preserving authenticated EXECUTE');
SET ROLE anon;
SELECT test_denied($q$SELECT can_add_task_to_list('30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001')$q$,'42501');
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub='';
SELECT test_denied($q$SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','QUALIFICATION')$q$,'42501');
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
SELECT test_denied($q$SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','QUALIFICATION')$q$,'42501');
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000006';
SELECT test_denied($q$SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','QUALIFICATION')$q$,'42501');
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','QUALIFICATION');
SELECT test_assert((SELECT assignee_id = auth.uid() AND created_by = auth.uid()
  AND title = 'Example Client discussion' AND due_date = (statement_timestamp() AT TIME ZONE 'Asia/Riyadh')::date
  AND due_date = (created_at AT TIME ZONE 'Asia/Riyadh')::date
  AND created_at BETWEEN now() - interval '1 minute' AND now()
  AND supervisor_id = '00000000-0000-0000-0000-000000000005' AND department = 'Sales'
  FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000001'), 'Contact title, actor, Riyadh date, server timestamp, department supervisor');
SELECT test_assert(EXISTS(SELECT 1 FROM get_my_day() item WHERE item->>'crm_deal_id'='40000000-0000-0000-0000-000000000001'), 'Generated Contact task is visible in the assignee My Day');
SELECT change_task_status((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000001'),'completed');
SELECT test_assert((SELECT status='completed' FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000001'), 'Contact completion has no CRM approval gate');
SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','LEAD');
RESET ROLE;
CREATE TEMP TABLE original_contact AS SELECT * FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000001';
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','QUALIFICATION');
SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','QUALIFICATION');
SELECT test_denied($q$SELECT ensure_crm_generated_task('40000000-0000-0000-0000-000000000001','CONTACT_DISCUSSION')$q$,'42501');
SELECT test_denied($q$SELECT * FROM crm_generated_tasks$q$,'42501');
SELECT test_denied($q$SELECT create_task_secure('{"title":"Spoof","crm_deal_id":"40000000-0000-0000-0000-000000000002","crm_workflow_kind":"CONTACT_DISCUSSION"}')$q$,'42501');
SELECT test_denied($q$SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','NEGOTIATION')$q$,'22023');
SELECT test_denied($q$SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','WON')$q$,'22023');
SELECT test_denied($q$SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000001','PITCH')$q$,'23514');
SELECT test_denied($q$SELECT start_crm_presentation_approval('40000000-0000-0000-0000-000000000002','QUOTE_PROPOSAL')$q$,'23514');
SELECT test_assert(NOT has_function_privilege(current_user,'decide_deal_approval(uuid,text,text)','EXECUTE')
 AND NOT has_function_privilege(current_user,'start_deal_approval(uuid,uuid,uuid,uuid)','EXECUTE')
 AND NOT has_function_privilege(current_user,'decide_crm_design_task_approval(uuid,text,text)','EXECUTE')
 AND NOT has_function_privilege(current_user,'finalize_crm_deal_approval(uuid)','EXECUTE')
 AND NOT has_function_privilege(current_user,'create_crm_design_task_for_deal(uuid)','EXECUTE'), 'All legacy approval and bypass RPCs retired');
SELECT test_assert(NOT has_function_privilege('anon','change_crm_deal_stage(uuid,text)','EXECUTE')
 AND NOT has_function_privilege('anon','start_crm_presentation_approval(uuid,text)','EXECUTE')
 AND NOT has_function_privilege('anon','create_project_from_won_deal_v2(uuid,jsonb)','EXECUTE'), 'Anonymous callers cannot execute CRM mutations');
RESET ROLE;
SELECT test_assert((SELECT count(*)=1 FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000001')
 AND (SELECT to_jsonb(t)=to_jsonb(o) FROM tasks t JOIN original_contact o ON t.id=o.id), 'Contact re-entry preserves the entire original completed task');
SELECT test_denied($q$UPDATE tasks SET crm_workflow_kind=NULL WHERE crm_deal_id='40000000-0000-0000-0000-000000000001'$q$,'42501');
SELECT test_denied($q$DELETE FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000001'$q$,'23503');
SELECT test_assert((SELECT count(*)=1 AND min(status)='PENDING' FROM crm_deal_approval_steps)
 AND (SELECT count(*)=1 AND min(status)='REJECTED' FROM crm_design_task_approval_steps), 'Historical approval rows preserved unchanged');
SELECT test_assert((SELECT stage='NEGOTIATION' FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000006'), 'Historical Discussion stage preserved');
INSERT INTO crm_deal_attachments(deal_id,category,file_url,file_type,description) VALUES
 ('40000000-0000-0000-0000-000000000002','QUOTATION','storage://crm-deal-files/quote.pdf','application/pdf','Quote'),
 ('40000000-0000-0000-0000-000000000002','PROPOSAL','storage://crm-deal-files/proposal.png','image/png','');
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
SELECT test_denied($q$SELECT start_crm_presentation_approval('40000000-0000-0000-0000-000000000002','QUOTE_PROPOSAL')$q$,'23514');
RESET ROLE;
UPDATE crm_deal_attachments SET description='Image description' WHERE category='PROPOSAL';
SET ROLE authenticated;
SELECT test_denied($q$SELECT start_crm_presentation_approval('40000000-0000-0000-0000-000000000002','QUOTE_PROPOSAL')$q$,'42501');
RESET ROLE;
SELECT test_assert((SELECT stage='LEAD' AND design_task_id IS NULL FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000002'), 'Denied Design list permission leaves deal unchanged');
RESET ROLE;
SELECT test_assert(NOT EXISTS(SELECT 1 FROM crm_generated_tasks WHERE deal_id='40000000-0000-0000-0000-000000000002'), 'Denied submission creates no ledger entry');
UPDATE task_lists SET can_add_users=ARRAY['00000000-0000-0000-0000-000000000001'::uuid];
SET ROLE authenticated;
SELECT start_crm_presentation_approval('40000000-0000-0000-0000-000000000002','QUOTE_PROPOSAL');
SELECT start_crm_presentation_approval('40000000-0000-0000-0000-000000000002','QUOTE_PROPOSAL');
SELECT test_assert((SELECT count(*)=1 AND min(assignee_id::text)='00000000-0000-0000-0000-000000000003'
 FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000002'), 'Complete proposal creates exactly one MQ-08 Design task');
RESET ROLE;
SELECT test_assert((SELECT stage='PITCH' AND design_task_id IS NOT NULL FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000002'), 'Submission and task creation commit together');
CREATE TEMP TABLE test_design_task_id AS SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000002';
GRANT SELECT ON test_design_task_id TO authenticated;
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
SELECT test_assert(NOT EXISTS(SELECT 1 FROM get_my_day() item WHERE item->>'crm_deal_id'='40000000-0000-0000-0000-000000000002'), 'Unrelated employee cannot see the Design task in My Day');
SELECT test_assert(NOT can_access_task((SELECT id FROM test_design_task_id), auth.uid()), 'Unrelated employee has no task access');
SELECT test_denied($q$SELECT change_task_status((SELECT id FROM test_design_task_id),'completed')$q$,'42501');
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
SELECT test_denied($q$SELECT change_task_status((SELECT id FROM test_design_task_id),'completed')$q$,'23514');
RESET ROLE;
INSERT INTO task_attachments(task_id,file_url,file_type) SELECT id,'storage://task-attachments/design.pdf','application/pdf'
 FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000002';
UPDATE tasks SET submission_links=ARRAY['storage://task-attachments/design.pdf'] WHERE crm_deal_id='40000000-0000-0000-0000-000000000002';
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
SELECT change_task_status((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000002'),'completed');
SELECT test_assert((SELECT status='completed' FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000002'), 'Authorized Design completion validates deliverables without approval');
SELECT test_denied($q$SELECT change_task_status((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000002'),'Pending Approval')$q$,'23514');
RESET ROLE;
UPDATE crm_deals SET title=repeat('x',255) WHERE id='40000000-0000-0000-0000-000000000004';
UPDATE crm_deals SET client_id=NULL WHERE id='40000000-0000-0000-0000-000000000004';
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
SELECT test_denied($q$SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000004','QUALIFICATION')$q$,'22001');
RESET ROLE;
SELECT test_assert((SELECT stage='LEAD' FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000004')
 AND NOT EXISTS(SELECT 1 FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000004')
 AND NOT EXISTS(SELECT 1 FROM crm_generated_tasks WHERE deal_id='40000000-0000-0000-0000-000000000004')
 AND NOT EXISTS(SELECT 1 FROM crm_deal_activity WHERE deal_id='40000000-0000-0000-0000-000000000004'), 'Task insertion failure rolls back stage, task, ledger and activity');
SELECT test_assert(EXISTS(SELECT 1 FROM task_activity WHERE action='TASK_CREATED')
 AND EXISTS(SELECT 1 FROM task_activity WHERE action='TASK_STATUS_CHANGED')
 AND EXISTS(SELECT 1 FROM notifications WHERE event_type='task_created' AND user_id='00000000-0000-0000-0000-000000000003')
 AND EXISTS(SELECT 1 FROM notifications WHERE event_type='crm_presentation_submitted'), 'Task audit, assignment notifications and CRM submission notifications preserved');
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
SELECT test_assert(NOT EXISTS (SELECT 1 FROM tasks task
 WHERE task.crm_deal_id='40000000-0000-0000-0000-000000000002'
   AND can_execute_task(task.id, '00000000-0000-0000-0000-000000000004')),
 'My Day execution predicate denies an unrelated employee');
SELECT test_assert(EXISTS (SELECT 1 FROM tasks task
 WHERE task.crm_deal_id='40000000-0000-0000-0000-000000000002'
   AND task.assignee_id='00000000-0000-0000-0000-000000000003'
   AND can_execute_task(task.id, task.assignee_id)),
 'My Day execution predicate permits the Design assignee');
RESET ROLE;
UPDATE profiles SET department_id='10000000-0000-0000-0000-000000000004' WHERE id='00000000-0000-0000-0000-000000000002';
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000002';
SELECT test_denied($q$SELECT create_project_from_won_deal_v2('40000000-0000-0000-0000-000000000003','{}')$q$,'23514');
RESET ROLE;
INSERT INTO crm_deal_attachments(deal_id,category,file_url,file_type,description) VALUES
 ('40000000-0000-0000-0000-000000000003','QUOTATION','storage://crm-deal-files/other.pdf','application/pdf','Quote');
SET ROLE authenticated;
SELECT test_denied($q$SELECT create_project_from_won_deal_v2('40000000-0000-0000-0000-000000000003','{"event_date":"2026-10-22","event_start_time":"10:00","client":{"name":"Client"},"installation_type":"INDOOR","assigned_people":["00000000-0000-0000-0000-000000000002"]}')$q$,'23514');
RESET ROLE;
SELECT test_assert((SELECT stage='LEAD' FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000003') AND NOT EXISTS(SELECT 1 FROM projects WHERE deal_id='40000000-0000-0000-0000-000000000003'), 'Authorized user cannot bypass Presentation by calling the Won RPC directly');
SET ROLE authenticated;
SELECT start_crm_presentation_approval('40000000-0000-0000-0000-000000000003','QUOTE');
SELECT test_assert(NOT EXISTS(SELECT 1 FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000003'), 'Quote-only submission does not create a Design task');
SELECT test_denied($q$SELECT create_project_from_won_deal_v2('40000000-0000-0000-0000-000000000003','{"project_amount":12}')$q$,'42501');
SELECT test_denied($q$SELECT create_project_from_won_deal_v2('40000000-0000-0000-0000-000000000003','{}')$q$,'P0001');
SELECT test_denied($q$SELECT create_project_from_won_deal_v2('40000000-0000-0000-0000-000000000003','{"event_date":"2026-10-22","event_end_date":"2026-10-21","event_start_time":"10:00","client":{"name":"Client"},"installation_type":"INDOOR"}')$q$,'P0001');
SELECT create_project_from_won_deal_v2('40000000-0000-0000-0000-000000000003','{"event_date":"2026-10-22","event_start_time":"10:00","client":{"name":"Client"},"installation_type":"INDOOR","assigned_people":["00000000-0000-0000-0000-000000000002"]}');
RESET ROLE;
SELECT test_assert((SELECT stage='WON' FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000003'), 'Won/order creation preserves contractual requirements without an approval status');
UPDATE projects SET paid_amount=42, project_amount=100 WHERE deal_id='40000000-0000-0000-0000-000000000003';
SET ROLE authenticated;
SELECT create_project_from_won_deal_v2('40000000-0000-0000-0000-000000000003','{"event_date":"2026-10-22","event_start_time":"10:00","client":{"name":"Client"},"installation_type":"INDOOR","assigned_people":["00000000-0000-0000-0000-000000000002"]}');
SELECT test_assert((SELECT count(*)=1 AND min(paid_amount)=42 AND min(project_amount)=100 FROM projects WHERE deal_id='40000000-0000-0000-0000-000000000003'), 'Order retries reuse the project and preserve financial values for nonfinancial actors');
SELECT test_assert(create_task_secure('{"title":"Regular task","status":"completed"}')->>'status'='Pending Approval', 'Ordinary Task Manager approval behavior is unchanged');
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
SELECT change_task_status('50000000-0000-0000-0000-000000000001','completed');
SELECT test_assert((SELECT status='completed' FROM tasks WHERE id='50000000-0000-0000-0000-000000000001'), 'Historical pending Design task can finish without deciding or deleting its approval history');
RESET ROLE;
SELECT test_assert(EXISTS(SELECT 1 FROM crm_generated_tasks WHERE deal_id='40000000-0000-0000-0000-000000000006' AND task_id='50000000-0000-0000-0000-000000000001'), 'Migration adopts the linked historical Design task');
SELECT test_assert((SELECT stage='LEAD' FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000004'), 'Shipped migration trigger rejects a new Discussion transition');
UPDATE crm_deals SET workflow_status='DESIGN_IN_PROGRESS' WHERE id='40000000-0000-0000-0000-000000000006';
SELECT test_assert((SELECT workflow_status='DESIGN_IN_PROGRESS' FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000006'), 'Legacy Discussion workflow-status changes remain valid without the retired approval gate');
UPDATE crm_deals SET stage='PITCH' WHERE id='40000000-0000-0000-0000-000000000006';

SELECT test_assert((SELECT stage='PITCH' FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000006'), 'Historical Discussion deals can progress out of the retired stage');


SELECT test_denied($q$UPDATE crm_deals SET lost_reason=NULL, stage='LOST' WHERE id='40000000-0000-0000-0000-000000000004'$q$,'23514');
SELECT test_denied($q$UPDATE crm_deals SET workflow_status='INVALID_STATUS' WHERE id='40000000-0000-0000-0000-000000000004'$q$,'23514');
UPDATE crm_deals SET stage='LOST', lost_reason='Customer postponed' WHERE id='40000000-0000-0000-0000-000000000004';
SELECT test_assert((SELECT stage='LOST' AND lost_reason='Customer postponed' FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000004'), 'Valid Lost transition succeeds when a reason is supplied');
-- The existing privileged deal-deletion path may detach tasks, while task
-- deletion on a live deal is restricted by the durable identity ledger.
DELETE FROM crm_deals WHERE id='40000000-0000-0000-0000-000000000006';
SELECT test_assert((SELECT crm_deal_id IS NULL AND status='completed' FROM tasks WHERE id='50000000-0000-0000-0000-000000000001'), 'Parent-deal deletion preserves and detaches the historical task');
