-- Synthetic RLS proof using the tracked permissive policies and both shipped
-- restrictive policies. No connected Supabase database is used.
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000007';
SELECT test_assert(can_access_crm(auth.uid()), 'Active MQ-20 Sales employee is legitimately CRM-authorized');
SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000007','QUALIFICATION');
SELECT test_assert((SELECT count(*)=1 FROM tasks
 WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'), 'MQ-20 Contact transition creates the generated discussion task');
SELECT test_assert((SELECT count(*)=1 FROM tasks
 WHERE crm_deal_id='40000000-0000-0000-0000-000000000007' AND created_by=auth.uid()
   AND assignee_id=auth.uid() AND crm_workflow_kind='CONTACT_DISCUSSION'),
 'MQ-20 can see only their own ledger-backed Contact discussion task');
SELECT test_assert(NOT EXISTS (SELECT 1 FROM tasks
 WHERE crm_deal_id='40000000-0000-0000-0000-000000000008'),
 'MQ-20 cannot see another employee Contact task');
SELECT test_assert(NOT EXISTS (SELECT 1 FROM tasks
 WHERE id='50000000-0000-0000-0000-000000000005'),
 'MQ-20 cannot see an unrelated task without task-access authorization');
SELECT test_assert((SELECT count(*)=1 FROM tasks
 WHERE id='50000000-0000-0000-0000-000000000009'),
 'MQ-20 retains existing authorized Ines/MQ-08 task visibility');
SELECT test_assert(NOT can_add_task_to_list('30000000-0000-0000-0000-000000000001',auth.uid()),
 'MQ-20 Contact visibility exception does not grant Design task-list access');
RESET ROLE;

SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
SELECT test_assert((SELECT count(*)=1 FROM tasks
 WHERE crm_deal_id='40000000-0000-0000-0000-000000000001' AND assignee_id=auth.uid()),
 'Ordinary CRM employee can see their assigned Contact task');
SELECT test_assert(can_add_task_to_list('30000000-0000-0000-0000-000000000001',auth.uid()),
 'Existing authorized task-list addition remains available');
SELECT test_assert(NOT EXISTS (SELECT 1 FROM tasks
 WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),
 'Ordinary CRM employee cannot see the MQ-20 employee private Contact task');
RESET ROLE;

SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000003';
SELECT test_assert((SELECT count(*)=1 FROM tasks
 WHERE crm_deal_id='40000000-0000-0000-0000-000000000002'
   AND crm_workflow_kind='QUOTE_PROPOSAL_DESIGN' AND assignee_id=auth.uid()),
 'MQ-08 Design assignee can see the assigned Design task');
RESET ROLE;

SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
SELECT test_assert(NOT EXISTS (SELECT 1 FROM tasks
 WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),
 'Unauthorized employee cannot see the MQ-20 Contact task');
SELECT test_assert(NOT can_access_crm(auth.uid()), 'Unauthorized employee remains outside CRM authorization');
SELECT test_denied($q$SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000010','QUALIFICATION')$q$,'42501');
RESET ROLE;

SELECT test_assert((SELECT permissive='RESTRICTIVE' AND qual ILIKE '%can_access_task%'
 FROM pg_policies WHERE schemaname='public' AND tablename='tasks'
   AND policyname='task_secure_access_select'),
 'Original restrictive task access policy remains installed and unchanged');
SELECT test_assert(NOT has_function_privilege('anon','public.can_view_own_crm_contact_task(uuid,uuid)','EXECUTE')
 AND has_function_privilege('authenticated','public.can_view_own_crm_contact_task(uuid,uuid)','EXECUTE'),
 'MQ-20 visibility helper is callable only by authenticated sessions');
