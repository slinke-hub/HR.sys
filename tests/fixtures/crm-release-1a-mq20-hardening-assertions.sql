-- Synthetic runtime checks against the same permissive/restrictive task RLS
-- policies and migration-installed table guards; no live Supabase is used.
CREATE FUNCTION test_mq20_write_related(p_table text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  CASE p_table
    WHEN 'task_dependencies' THEN INSERT INTO task_dependencies(predecessor_task_id,successor_task_id)
      VALUES ('50000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000002');
    WHEN 'task_waiting_history' THEN INSERT INTO task_waiting_history(task_id,category)
      VALUES ('50000000-0000-0000-0000-000000000001','DEPENDENCY');
    WHEN 'task_blocker_history' THEN INSERT INTO task_blocker_history(task_id,category)
      VALUES ('50000000-0000-0000-0000-000000000001','OTHER');
    WHEN 'task_lists' THEN INSERT INTO task_lists(name) VALUES ('forbidden MQ-20 list');
    ELSE RAISE EXCEPTION 'unexpected test table';
  END CASE;
END $$;
GRANT EXECUTE ON FUNCTION test_mq20_write_related(text) TO authenticated;

SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000008','QUALIFICATION');
RESET ROLE;

SET ROLE authenticated;
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000007';
SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000007','QUALIFICATION');
SELECT test_assert(public.can_access_task((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'), auth.uid()),
  'MQ-20 reads their own ledger-backed Contact task');
SELECT test_assert(NOT public.can_access_task((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),
  '00000000-0000-0000-0000-000000000001'), 'MQ-20 cannot spoof another task-reader identity');
SELECT test_assert(NOT public.can_access_task((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000008'), auth.uid()),
  'MQ-20 cannot read another employee Contact task');
SELECT test_assert(public.can_access_task('50000000-0000-0000-0000-000000000001', auth.uid()),
  'MQ-20 retains the existing authorized MQ-08 task grant');
SELECT test_assert(public.get_task_secure((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000008')) IS NULL,
  'SECURITY DEFINER task reader does not disclose another employees Contact task');
SELECT test_denied($q$SELECT create_task_secure('{"title":"MQ20 must not create a generic task"}'::jsonb)$q$,'42501');
SELECT test_denied($q$SELECT update_task_secure((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'), '{"title":"forged"}'::jsonb)$q$,'42501');
SELECT test_denied($q$SELECT delete_task_secure((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'))$q$,'42501');
SELECT test_denied($q$SELECT change_task_status((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),'completed')$q$,'42501');
SELECT test_denied($q$SELECT add_task_comment((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),'forbidden', '[]'::jsonb)$q$,'42501');
SELECT test_denied($q$SELECT register_task_attachment((SELECT id FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),'storage://task-attachments/forbidden','forbidden.txt','text/plain',1,'TASK',false)$q$,'42501');
SELECT test_denied($q$SELECT test_mq20_write_related('task_dependencies')$q$,'42501');
SELECT test_denied($q$SELECT test_mq20_write_related('task_waiting_history')$q$,'42501');
SELECT test_denied($q$SELECT test_mq20_write_related('task_blocker_history')$q$,'42501');
SELECT test_denied($q$SELECT test_mq20_write_related('task_lists')$q$,'42501');
SELECT test_assert((SELECT status='todo' AND title='Example Client discussion' FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000007'),
  'Denied task writes preserve the original Contact task');
RESET ROLE;
DROP FUNCTION test_mq20_write_related(text);

SELECT test_assert((SELECT count(*)=1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass
  AND tgname='mq20_task_service_view_only' AND tgenabled='O'), 'MQ-20 task row guard is installed and enabled');
SELECT test_assert((SELECT count(*)=6 FROM pg_trigger WHERE tgname LIKE 'mq20_view_only_%' AND NOT tgisinternal),
  'MQ-20 related-row guards cover comments, attachments, dependencies, productivity history, and task lists');
