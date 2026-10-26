-- Synthetic dependency privacy tests. No live Supabase data or writes are used.
SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000007';
SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000009','QUALIFICATION');
RESET ROLE;
-- Clear the synthetic authenticated claim before privileged fixture setup so
-- the MQ-20 service-boundary triggers do not treat test data inserts as user writes.
SET request.jwt.claim.sub='';

UPDATE departments SET head_id='00000000-0000-0000-0000-000000000001' WHERE name='Other';
INSERT INTO tasks(id,title,description,assignee_id,assignee_ids,created_by,supervisor_id,status,due_date)
VALUES
 ('50000000-0000-0000-0000-000000000002','Ordinary visible predecessor','ordinary predecessor',
  '00000000-0000-0000-0000-000000000001',ARRAY['00000000-0000-0000-0000-000000000001'::uuid],
  '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005','todo',CURRENT_DATE+10),
 ('50000000-0000-0000-0000-000000000004','Ordinary visible successor','ordinary task',
  '00000000-0000-0000-0000-000000000001',ARRAY['00000000-0000-0000-0000-000000000001'::uuid],
  '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005','todo',CURRENT_DATE+5),
 ('50000000-0000-0000-0000-000000000005','Secret hidden dependency task','private description',
  '00000000-0000-0000-0000-000000000002',ARRAY['00000000-0000-0000-0000-000000000002'::uuid],
  '00000000-0000-0000-0000-000000000002',NULL,'todo',CURRENT_DATE+10);
UPDATE tasks SET department='Other'
WHERE id IN ('50000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000004');
UPDATE tasks SET department='Marketing' WHERE id='50000000-0000-0000-0000-000000000005';

INSERT INTO task_dependencies(predecessor_task_id,successor_task_id,created_by) VALUES
 ('50000000-0000-0000-0000-000000000001',
  (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),
  '00000000-0000-0000-0000-000000000005'),
 ('50000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-000000000001'),
 ('50000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000005',
  '00000000-0000-0000-0000-000000000001'),
 ('50000000-0000-0000-0000-000000000005',
  (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009'),
  '00000000-0000-0000-0000-000000000001');

INSERT INTO task_activity(task_id,actor_id,action,metadata) VALUES
 ((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009'),
  '00000000-0000-0000-0000-000000000001','TASK_DEPENDENCY_CREATED',
  jsonb_build_object('dependency_id','60000000-0000-0000-0000-000000000002',
    'predecessor_task_id','50000000-0000-0000-0000-000000000005'));

SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000007';
SELECT test_assert(NOT public.can_view_task_dependency(
  '50000000-0000-0000-0000-000000000005',
  (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009'),auth.uid()),
  'MQ-20 cannot see a dependency with a hidden endpoint');
SELECT test_assert(public.can_view_task_dependency(
  '50000000-0000-0000-0000-000000000001',
  (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),auth.uid()),
  'MQ-20 retains a dependency between independently visible tasks');
SELECT test_assert((SELECT count(*)=0 FROM public.list_task_dependencies_secure(
  (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009'))),
  'Dependency RPC hides rows, identifiers, and endpoint metadata when the other task is hidden');
SELECT test_assert((SELECT count(*)=1 FROM public.list_task_dependencies_secure(
  (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'))),
  'Dependency RPC preserves an authorized Ines/MQ-08 dependency');
SELECT test_assert(NOT has_function_privilege('authenticated',
  'public.task_dependency_blocked_visible(uuid,uuid)','EXECUTE'),
  'Internal dependency visibility helper is not directly callable by authenticated clients');
SELECT test_assert(NOT EXISTS (
  SELECT 1 FROM public.list_task_dependency_history_secure(
    (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009'))
  WHERE metadata::text LIKE '%Secret hidden dependency task%'
     OR metadata::text LIKE '%50000000-0000-0000-0000-000000000005%'),
  'Dependency history RPC omits hidden endpoint identifiers and metadata');
SELECT test_assert(NOT EXISTS (
  SELECT 1 FROM public.list_task_activity_secure(
    (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009'))
  WHERE action LIKE 'TASK_DEPENDENCY%'
     AND metadata::text LIKE '%50000000-0000-0000-0000-000000000005%'),
  'Task activity RPC omits dependency history referencing hidden endpoints');
SELECT test_assert(NOT EXISTS (
  SELECT 1 FROM task_activity
  WHERE task_id=(SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009')
    AND action LIKE 'TASK_DEPENDENCY%'),
  'Direct task activity RLS hides dependency history referencing hidden endpoints');
SELECT test_assert(NOT EXISTS (
  SELECT 1 FROM public.get_task_secure(
    (SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009')) AS result(item)
  WHERE COALESCE(item->>'blocking_task_title','')='Secret hidden dependency task'
     OR COALESCE(item->>'dependency_blocked','false')='true'),
  'get_task_secure does not leak hidden blocker metadata or dependency state');
SELECT test_assert(NOT EXISTS (
  SELECT 1 FROM public.list_accessible_tasks_secure() AS result(item)
  WHERE item->>'id'=(SELECT id::text FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009')
    AND (COALESCE(item->>'blocking_task_title','')='Secret hidden dependency task'
      OR COALESCE(item->>'dependency_blocked','false')='true')),
  'Task-list RPC does not leak hidden blocker metadata or dependency state');
SELECT test_assert(NOT EXISTS (
  SELECT 1 FROM public.get_my_day() AS result(item)
  WHERE item->>'id'=(SELECT id::text FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000009')
    AND (COALESCE(item->>'blocking_task_title','')='Secret hidden dependency task'
      OR COALESCE(item->>'dependency_blocked','false')='true')),
  'My Day does not leak hidden blocker metadata or dependency state');
RESET ROLE;

SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
SELECT test_assert((SELECT count(*)=1 FROM public.list_task_dependencies_secure(
  '50000000-0000-0000-0000-000000000002')),
  'Ordinary employee retains authorized dependency access between visible tasks');
WITH handoff AS MATERIALIZED (
  SELECT public.complete_and_hand_off_task('50000000-0000-0000-0000-000000000002') AS result
)
SELECT test_assert(
  (handoff.result->'successor_task_ids')::text NOT LIKE '%' ||
    '50000000-0000-0000-0000-000000000005' || '%'
  AND (handoff.result->'successor_task_ids')::text LIKE '%50000000-0000-0000-0000-000000000004%',
  'Completion/handoff response filters hidden successors but keeps visible successor IDs')
FROM handoff;
RESET ROLE;
