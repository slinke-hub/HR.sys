-- Read-only staging preflight. Invoke only through the staging-only runner.
\set ON_ERROR_STOP on
-- Synthetic PostgreSQL tests may opt in explicitly with -v synthetic_test=on.
-- The staging runner never sets this variable; normal identity checks stay strict.
\if :{?synthetic_test}
SELECT set_config('crm.release_synthetic_test', :'synthetic_test', false);
\endif
BEGIN READ ONLY;

DO $preflight$
DECLARE tls_ok boolean; required_table text; required_column text;
BEGIN
  IF (current_database() <> 'postgres'
       AND NOT (current_database() = 'crm_release_1a_test'
                AND current_setting('crm.release_synthetic_test', true) = 'on'))
     OR current_user <> 'postgres'
     OR current_setting('server_version') NOT LIKE '17.6%' THEN
    RAISE EXCEPTION 'Expected staging database postgres, role postgres, PostgreSQL 17.6; got %, %, %',
      current_database(), current_user, current_setting('server_version');
  END IF;
  SELECT ssl INTO tls_ok FROM pg_stat_ssl WHERE pid=pg_backend_pid();
  IF tls_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'TLS is not active on this connection'; END IF;

  IF to_regclass('public.crm_deals') IS NULL OR to_regclass('public.tasks') IS NULL
     OR to_regclass('public.task_lists') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.crm_deals'::regclass
       AND attname='stage' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.crm_deals'::regclass
       AND attname='workflow_status' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.crm_deals'::regclass
       AND attname='lost_reason' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass
       AND attname='crm_deal_id' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass
       AND attname='crm_workflow_kind' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Required CRM/task schema prerequisites are missing';
  END IF;
  FOREACH required_table IN ARRAY ARRAY[
    'task_comments','task_attachments','task_dependencies','task_activity','profiles','projects'
  ] LOOP
    IF to_regclass(format('public.%I', required_table)) IS NULL THEN
      RAISE EXCEPTION 'Required table public.% is missing', required_table;
    END IF;
  END LOOP;
  FOREACH required_column IN ARRAY ARRAY[
    'id','created_by','assignee_id','assignee_ids','supervisor_id','visible_to',
    'task_list_id','crm_deal_id','crm_workflow_kind','title','status'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass
       AND attname=required_column AND NOT attisdropped) THEN
      RAISE EXCEPTION 'Required tasks column % is missing', required_column;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.task_comments'::regclass AND attname='task_id' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.task_attachments'::regclass AND attname='task_id' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.task_attachments'::regclass AND attname='file_url' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.task_dependencies'::regclass AND attname='predecessor_task_id' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.task_dependencies'::regclass AND attname='successor_task_id' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.task_activity'::regclass AND attname='metadata' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Required task child/dependency/activity columns are missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.crm_deals'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.tasks'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_lists'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_comments'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_attachments'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_activity'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'Expected CRM/task/comment/attachment/activity RLS is not enabled';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass
     AND tgname='crm_deals_enforce_workflow_transition' AND NOT tgisinternal AND tgenabled='O'
     AND tgfoid='public.enforce_deal_workflow_transition()'::regprocedure)
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass
     AND tgname='crm_deal_workflow_transition' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CRM workflow trigger baseline conflicts with unapplied Release 1A';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.enforce_crm_deal_contact_requirements()'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.protect_lost_crm_deal_edits()'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.record_failed_login(text)'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.is_mq20_profile(uuid)'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.is_ines_modani_task(uuid)'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_view_task_list(uuid,uuid)'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_view_task_list_via_employee_grant(uuid,uuid)'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_assign_tasks_company_wide(uuid)'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_marketing_manager_edit_task(uuid,uuid)'::regprocedure)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_view_task_via_employee_grant(uuid,uuid)'::regprocedure) THEN
    RAISE EXCEPTION 'Expected staging CRM/security prerequisite functions are absent';
  END IF;
  IF to_regclass('public.crm_generated_tasks') IS NOT NULL THEN
    RAISE EXCEPTION 'crm_generated_tasks exists although all Release 1A migrations are recorded absent';
  END IF;
END
$preflight$;

SELECT current_database() AS database_name,
       current_user AS effective_role,
       current_setting('server_version') AS server_version,
       ssl, version AS tls_version, cipher
FROM pg_stat_ssl WHERE pid=pg_backend_pid();

-- Preserve these known historical records. The full ledger is also captured by
-- the runner and compared after each approved migration/ledger checkpoint.
SELECT version::text, name
FROM supabase_migrations.schema_migrations
WHERE version::text = ANY (ARRAY[
  '20260830000000','20261001100000','20261005100000','20261005110000',
  '20261022100000','20261024100000','20261026100000','20261027100000'
])
ORDER BY version;

DO $ledger_preflight$
DECLARE missing_history text[];
BEGIN
  SELECT array_agg(v) INTO missing_history
  FROM unnest(ARRAY['20260830000000','20261001100000','20261005100000','20261005110000']) v
  WHERE NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations m WHERE m.version::text=v);
  IF missing_history IS NOT NULL THEN RAISE EXCEPTION 'Required historical ledger versions missing: %', missing_history; END IF;
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
             WHERE version::text = ANY (ARRAY['20261022100000','20261024100000','20261026100000','20261027100000'])) THEN
    RAISE EXCEPTION 'One or more Release 1A versions are already recorded; stop for reconciliation';
  END IF;
END
$ledger_preflight$;

ROLLBACK;
