-- Read-only, migration-specific catalog assertions for HR.sys CRM Release 1A.
-- Invoke with psql -v migration_version=<exact-version> -f this-file.
-- This file performs no writes; it checks catalog definitions and grants only.
\set ON_ERROR_STOP on
-- Synthetic PostgreSQL tests may opt in explicitly with -v synthetic_test=on.
-- The staging runner never sets this variable; normal identity checks stay strict.
\if :{?synthetic_test}
SELECT set_config('crm.release_synthetic_test', :'synthetic_test', false);
\endif
BEGIN READ ONLY;
SET LOCAL crm.release_migration_version = :'migration_version';

DO $release_assertions$
DECLARE
  v text := current_setting('crm.release_migration_version');
  ok boolean;
  fn record;
  guarded_table text;
BEGIN
  IF (current_database() <> 'postgres'
       AND NOT (current_database() = 'crm_release_1a_test'
                AND current_setting('crm.release_synthetic_test', true) = 'on'))
     OR current_user <> 'postgres'
     OR current_setting('server_version') NOT LIKE '17.6%'
     OR NOT EXISTS (SELECT 1 FROM pg_stat_ssl WHERE pid = pg_backend_pid() AND ssl) THEN
    RAISE EXCEPTION 'Post-check identity/TLS/version mismatch';
  END IF;
  IF v NOT IN ('20261022100000','20261024100000','20261026100000','20261027100000') THEN
    RAISE EXCEPTION 'Unexpected migration checkpoint: %', v;
  END IF;

  IF v >= '20261022100000' THEN
    IF to_regclass('public.crm_generated_tasks') IS NULL
       OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.crm_generated_tasks'::regclass)
       OR has_table_privilege('anon','public.crm_generated_tasks','SELECT')
       OR has_table_privilege('authenticated','public.crm_generated_tasks','SELECT') THEN
      RAISE EXCEPTION 'crm_generated_tasks missing RLS or exposes table access';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint c
      WHERE c.conrelid='public.tasks'::regclass
        AND c.conname='tasks_crm_workflow_kind_check'
        AND c.contype='c' AND c.convalidated
        AND pg_get_constraintdef(c.oid) ILIKE '%CONTACT_DISCUSSION%'
        AND pg_get_constraintdef(c.oid) ILIKE '%QUOTE_PROPOSAL_DESIGN%'
    ) THEN RAISE EXCEPTION 'CRM task-kind constraint missing, invalid, or incomplete'; END IF;
    IF (SELECT count(*) FROM pg_trigger t
        WHERE t.tgrelid='public.crm_deals'::regclass AND NOT t.tgisinternal
          AND t.tgfoid='public.enforce_deal_workflow_transition()'::regprocedure
          AND t.tgenabled='O'
          AND pg_get_triggerdef(t.oid) ILIKE '%stage%workflow_status%lost_reason%') <> 1
       OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass
                  AND tgname='crm_deals_enforce_workflow_transition' AND NOT tgisinternal) THEN
      RAISE EXCEPTION 'CRM workflow trigger inventory/event coverage mismatch';
    END IF;
    IF has_function_privilege('anon','public.can_add_task_to_list(uuid,uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.can_add_task_to_list(uuid,uuid)','EXECUTE')
       OR has_function_privilege('anon','public.change_crm_deal_stage(uuid,text)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.change_crm_deal_stage(uuid,text)','EXECUTE')
       OR has_function_privilege('anon','public.create_project_from_won_deal_v2(uuid,jsonb)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.create_project_from_won_deal_v2(uuid,jsonb)','EXECUTE') THEN
      RAISE EXCEPTION 'CRM/task-list RPC effective grants mismatch';
    END IF;
    SELECT p.prosecdef, pg_get_userbyid(p.proowner) AS owner,
           p.proconfig @> ARRAY['search_path=public, pg_temp'] AS pinned
      INTO fn FROM pg_proc p WHERE p.oid='public.ensure_crm_generated_task(uuid,text)'::regprocedure;
    IF NOT FOUND OR fn.prosecdef IS DISTINCT FROM true OR fn.owner <> 'postgres' OR NOT fn.pinned
       OR has_function_privilege('anon','public.ensure_crm_generated_task(uuid,text)','EXECUTE')
       OR has_function_privilege('authenticated','public.ensure_crm_generated_task(uuid,text)','EXECUTE') THEN
      RAISE EXCEPTION 'Generated-task helper ownership/security/grants mismatch';
    END IF;
    SELECT count(DISTINCT p.proname)=3 AND bool_and(p.prosecdef
             AND pg_get_userbyid(p.proowner)='postgres'
             AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
      INTO ok FROM pg_proc p WHERE p.proname IN
       ('change_crm_deal_stage','start_crm_presentation_approval','create_project_from_won_deal_v2')
       AND p.pronamespace='public'::regnamespace;
    IF ok IS DISTINCT FROM true
       OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.enforce_deal_workflow_transition()'::regprocedure
          AND NOT p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
          AND p.proconfig @> ARRAY['search_path=public, pg_temp']) THEN
      RAISE EXCEPTION 'CRM workflow RPC/trigger-function security attributes mismatch';
    END IF;
  END IF;

  IF v >= '20261024100000' THEN
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.can_view_own_crm_contact_task(uuid,uuid)'::regprocedure
      AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
      AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
       OR has_function_privilege('anon','public.can_view_own_crm_contact_task(uuid,uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.can_view_own_crm_contact_task(uuid,uuid)','EXECUTE')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='tasks'
          AND policyname='mq20_only_ines_tasks_select' AND permissive='RESTRICTIVE' AND cmd='SELECT'
          AND qual ILIKE '%is_mq20_profile%' AND qual ILIKE '%is_ines_modani_task%'
          AND qual ILIKE '%can_view_own_crm_contact_task%') THEN
      RAISE EXCEPTION 'Contact-task visibility helper or restrictive task policy mismatch';
    END IF;
  END IF;

  IF v >= '20261026100000' THEN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass
       AND tgname='mq20_task_service_view_only' AND NOT tgisinternal AND tgenabled='O'
       AND tgfoid='public.enforce_mq20_task_service_boundaries()'::regprocedure)
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='task_comments'
          AND policyname='mq20_only_ines_task_comments_select' AND permissive='RESTRICTIVE' AND cmd='SELECT'
          AND qual ILIKE '%crm_is_own_generated_contact_task%' AND qual ILIKE '%is_ines_modani_task%')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='task_attachments'
          AND policyname='mq20_only_ines_task_attachments_select' AND permissive='RESTRICTIVE' AND cmd='SELECT'
          AND qual ILIKE '%crm_is_own_generated_contact_task%' AND qual ILIKE '%is_ines_modani_task%')
       OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_comments'::regclass AND relrowsecurity)
       OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_attachments'::regclass AND relrowsecurity)
       OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_lists'::regclass AND relrowsecurity) THEN
      RAISE EXCEPTION 'MQ-20 task/child-row read-only guard inventory mismatch';
    END IF;
    FOREACH guarded_table IN ARRAY ARRAY[
      'tasks','task_comments','task_attachments','task_dependencies',
      'task_waiting_history','task_blocker_history','task_lists'
    ] LOOP
      IF to_regclass(format('public.%I', guarded_table)) IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM pg_trigger t
           WHERE t.tgrelid=to_regclass(format('public.%I', guarded_table))
             AND t.tgname=CASE WHEN guarded_table='tasks' THEN 'mq20_task_service_view_only'
                              ELSE 'mq20_view_only_' || guarded_table END
             AND NOT t.tgisinternal AND t.tgenabled='O'
             AND t.tgfoid='public.enforce_mq20_task_service_boundaries()'::regprocedure
         ) THEN
        RAISE EXCEPTION 'MQ-20 service-boundary trigger missing or disabled on public.%', guarded_table;
      END IF;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.crm_is_own_generated_contact_task(uuid,uuid)'::regprocedure
       AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
       AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
       OR has_function_privilege('anon','public.crm_is_own_generated_contact_task(uuid,uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.crm_is_own_generated_contact_task(uuid,uuid)','EXECUTE') THEN
      RAISE EXCEPTION 'MQ-20 Contact-task helper ownership/security/grants mismatch';
    END IF;
    SELECT count(DISTINCT p.proname)=5 AND bool_and(p.prosecdef
             AND pg_get_userbyid(p.proowner)='postgres'
             AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
      INTO ok FROM pg_proc p WHERE p.proname IN
       ('can_access_task','can_manage_task','can_execute_task',
        'can_manage_task_attachments','can_read_task_attachment_file')
       AND p.pronamespace='public'::regnamespace;
    IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'MQ-20 authorization helper security attributes mismatch'; END IF;
  END IF;

  IF v >= '20261027100000' THEN
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_dependencies'::regclass AND relrowsecurity)
       OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_activity'::regclass AND relrowsecurity)
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='task_dependencies'
          AND policyname='task_dependencies_secure_select' AND cmd='SELECT')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='task_activity'
          AND policyname='task_activity_secure_select' AND cmd='SELECT'
          AND qual ILIKE '%task_activity_dependency_visible%')
       OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='task_dependencies'
          AND policyname='task_dependencies_secure_select' AND cmd='SELECT'
          AND qual ILIKE '%can_view_task_dependency%') THEN
      RAISE EXCEPTION 'Dependency/activity RLS or policy inventory mismatch';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.can_view_task_dependency(uuid,uuid,uuid)'::regprocedure
       AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
       AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
       OR has_function_privilege('anon','public.can_view_task_dependency(uuid,uuid,uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.can_view_task_dependency(uuid,uuid,uuid)','EXECUTE')
       OR has_function_privilege('authenticated','public.task_dependency_blocked_visible(uuid,uuid)','EXECUTE')
       OR has_function_privilege('anon','public.list_task_dependencies_secure(uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.list_task_dependencies_secure(uuid)','EXECUTE') THEN
      RAISE EXCEPTION 'Dependency visibility helper ownership/security/grants mismatch (helper=%, helper_owner=%, anon_can_view=%, auth_can_view=%, auth_blocked=%, anon_list=%, auth_list=%)',
        EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.can_view_task_dependency(uuid,uuid,uuid)'::regprocedure
          AND p.prosecdef AND p.proconfig @> ARRAY['search_path=public, pg_temp']),
        (SELECT pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid='public.can_view_task_dependency(uuid,uuid,uuid)'::regprocedure),
        has_function_privilege('anon','public.can_view_task_dependency(uuid,uuid,uuid)','EXECUTE'),
        has_function_privilege('authenticated','public.can_view_task_dependency(uuid,uuid,uuid)','EXECUTE'),
        has_function_privilege('authenticated','public.task_dependency_blocked_visible(uuid,uuid)','EXECUTE'),
        has_function_privilege('anon','public.list_task_dependencies_secure(uuid)','EXECUTE'),
        has_function_privilege('authenticated','public.list_task_dependencies_secure(uuid)','EXECUTE');
    END IF;
    SELECT count(DISTINCT p.proname)=11 AND bool_and(p.prosecdef
             AND pg_get_userbyid(p.proowner)='postgres'
             AND p.proconfig @> ARRAY['search_path=public, pg_temp'])
      INTO ok FROM pg_proc p WHERE p.proname IN
       ('can_view_task_dependency','task_dependency_blocked_visible','task_activity_dependency_visible',
        'list_task_dependencies_secure','list_task_dependency_history_secure','list_task_dependency_blockers_secure',
        'complete_task_productivity','complete_and_hand_off_task','list_accessible_tasks_secure',
        'get_my_day','list_task_activity_secure') AND p.pronamespace='public'::regnamespace;
    IF ok IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Dependency/history/task-list RPC security attributes mismatch';
    END IF;
    IF has_function_privilege('anon','public.list_task_dependency_history_secure(uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.list_task_dependency_history_secure(uuid)','EXECUTE')
       OR has_function_privilege('anon','public.list_task_dependency_blockers_secure()','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.list_task_dependency_blockers_secure()','EXECUTE') THEN
      RAISE EXCEPTION 'Dependency RPC effective grants mismatch';
    END IF;
    IF has_function_privilege('anon','public.task_activity_dependency_visible(uuid,text,jsonb,uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.task_activity_dependency_visible(uuid,text,jsonb,uuid)','EXECUTE')
       OR has_function_privilege('anon','public.task_dependency_blocked_visible(uuid,uuid)','EXECUTE')
       OR has_function_privilege('authenticated','public.task_dependency_blocked_visible(uuid,uuid)','EXECUTE')
       OR has_function_privilege('anon','public.complete_task_productivity(uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.complete_task_productivity(uuid)','EXECUTE')
       OR has_function_privilege('anon','public.complete_and_hand_off_task(uuid,uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.complete_and_hand_off_task(uuid,uuid)','EXECUTE')
       OR has_function_privilege('anon','public.list_task_dependencies_secure(uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.list_task_dependencies_secure(uuid)','EXECUTE')
       OR has_function_privilege('anon','public.list_task_activity_secure(uuid)','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.list_task_activity_secure(uuid)','EXECUTE')
       OR has_function_privilege('anon','public.list_accessible_tasks_secure()','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.list_accessible_tasks_secure()','EXECUTE')
       OR has_function_privilege('anon','public.get_my_day()','EXECUTE')
       OR NOT has_function_privilege('authenticated','public.get_my_day()','EXECUTE') THEN
      RAISE EXCEPTION 'Dependency/activity helper effective grants mismatch';
    END IF;
  END IF;
END
$release_assertions$;

ROLLBACK;
