-- Deterministic, read-only preflight for first application of Project
-- Operations Phase 1. Catalog metadata only; no business rows are read.
-- Expected execution context is the staging database owner (postgres).

WITH expected_functions(signature, function_name, must_exist, must_be_absent) AS (
  VALUES
    ('public.get_crm_client_secure(uuid)', 'get_crm_client_secure', true, false),
    ('public.get_crm_client_secure_project_ops_base(uuid)', 'get_crm_client_secure_project_ops_base', false, true),
    ('public.project_operational_snapshot(uuid,uuid)', 'project_operational_snapshot', false, true),
    ('public.create_project_secure(jsonb)', 'create_project_secure', true, false),
    ('public.update_project_secure(uuid,jsonb)', 'update_project_secure', true, false),
    ('public.list_accessible_projects_secure()', 'list_accessible_projects_secure', true, false),
    ('public.get_project_detail_secure(uuid)', 'get_project_detail_secure', true, false),
    ('public.list_project_command_center(integer,boolean,integer)', 'list_project_command_center', true, false),
    ('public.get_project_operational_summary(uuid)', 'get_project_operational_summary', true, false),
    ('public.get_project_health(uuid)', 'get_project_health', true, false),
    ('public.get_project_completion_readiness(uuid)', 'get_project_completion_readiness', false, true),
    ('public.change_project_status(uuid,text)', 'change_project_status', true, false),
    ('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)', 'create_project_from_won_deal', true, false),
    ('public.can_access_project(uuid,uuid)', 'can_access_project', true, false),
    ('public.is_project_portfolio_admin(uuid)', 'is_project_portfolio_admin', true, false),
    ('public.task_dependency_blocked(uuid)', 'task_dependency_blocked', true, false),
    ('public.can_view_business_financials(uuid)', 'can_view_business_financials', true, false),
    ('public.can_access_task(uuid,uuid)', 'can_access_task', true, false),
    ('public.list_project_updates_secure(uuid)', 'list_project_updates_secure', true, false),
    ('public.list_project_todos_secure(uuid)', 'list_project_todos_secure', true, false),
    ('public.list_project_shared_attachments(uuid)', 'list_project_shared_attachments', true, false)
), function_state AS (
  SELECT expected.signature, expected.function_name, expected.must_exist, expected.must_be_absent,
    proc.oid, owner_role.rolname AS function_owner, proc.prosecdef AS security_definer,
    proc.proconfig AS function_config,
    CASE WHEN proc.oid IS NULL THEN false ELSE has_function_privilege('authenticated', proc.oid, 'EXECUTE') END AS authenticated_execute,
    CASE WHEN proc.oid IS NULL THEN false ELSE has_function_privilege('anon', proc.oid, 'EXECUTE') END AS anon_execute
  FROM expected_functions expected
  LEFT JOIN pg_proc proc ON proc.oid = to_regprocedure(expected.signature)
  LEFT JOIN pg_roles owner_role ON owner_role.oid = proc.proowner
), required_columns(table_name, column_name) AS (
  VALUES
    ('projects','id'),('projects','project_name'),('projects','project_type'),('projects','project_status'),
    ('projects','lifecycle_status'),('projects','assigned_people'),('projects','project_manager_id'),
    ('projects','created_by'),('projects','priority'),('projects','start_date'),('projects','end_date'),
    ('projects','event_date'),('projects','client_name'),('projects','client_id'),('projects','deal_id'),
    ('projects','project_amount'),('projects','paid_amount'),('projects','budget_amount'),('projects','actual_cost'),
    ('projects','health_status'),('projects','progress_percent'),
    ('profiles','id'),('profiles','full_name'),('profiles','display_name'),('profiles','display_name_ar'),('profiles','employee_id'),
    ('tasks','id'),('tasks','project_id'),('tasks','title'),('tasks','status'),('tasks','work_state'),
    ('tasks','due_date'),('tasks','priority'),('tasks','archived_at'),('tasks','created_at'),
    ('project_todos','project_id'),('project_todos','status'),('project_todos','due_at'),
    ('project_updates','project_id'),('project_updates','author_id'),('project_updates','update_type'),('project_updates','summary'),
    ('crm_clients','id'),('crm_clients','name'),('crm_clients','company')
), column_state AS (
  SELECT required.table_name, required.column_name, attribute.attnum IS NOT NULL AS present
  FROM required_columns required
  LEFT JOIN pg_class relation ON relation.relname = required.table_name
    AND relation.relnamespace = 'public'::regnamespace
  LEFT JOIN pg_attribute attribute ON attribute.attrelid = relation.oid
    AND attribute.attname = required.column_name AND attribute.attnum > 0 AND NOT attribute.attisdropped
), api_functions AS (
  SELECT * FROM function_state WHERE function_name IN (
    'get_crm_client_secure','create_project_secure','update_project_secure',
    'list_accessible_projects_secure','get_project_detail_secure','list_project_command_center',
    'get_project_operational_summary','get_project_health','change_project_status'
  )
), security_functions AS (
  SELECT * FROM function_state WHERE function_name IN (
    'get_crm_client_secure','create_project_secure','update_project_secure',
    'list_accessible_projects_secure','get_project_detail_secure','list_project_command_center',
    'get_project_operational_summary','get_project_health','change_project_status'
  )
), migration_state AS (
  SELECT to_regclass('supabase_migrations.schema_migrations') IS NOT NULL AS history_table_exists,
    EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261002090000') AS recorded,
    to_regprocedure('public.project_operational_snapshot(uuid,uuid)') IS NOT NULL AS snapshot_exists,
    to_regprocedure('public.get_project_completion_readiness(uuid)') IS NOT NULL AS readiness_exists
), conflicting_overloads AS (
  SELECT count(*)::integer AS unexpected_count
  FROM pg_proc proc
  JOIN pg_namespace namespace ON namespace.oid = proc.pronamespace
  WHERE namespace.nspname = 'public'
    AND proc.proname IN (
      'get_crm_client_secure','create_project_secure','update_project_secure',
      'list_accessible_projects_secure','get_project_detail_secure','list_project_command_center',
      'get_project_operational_summary','get_project_health','change_project_status',
      'project_operational_snapshot','get_project_completion_readiness'
    )
    AND NOT EXISTS (
      SELECT 1 FROM expected_functions expected
      WHERE expected.function_name = proc.proname
        AND to_regprocedure(expected.signature) = proc.oid
    )
), project_access_state AS (
  SELECT relation.relrowsecurity AS rls_enabled,
    has_table_privilege('anon','public.projects','SELECT') AS anon_table_select,
    has_table_privilege('authenticated','public.projects','SELECT') AS authenticated_table_select,
    has_any_column_privilege('authenticated','public.projects','SELECT') AS authenticated_column_select,
    (SELECT count(*)::integer FROM pg_policies policy
      WHERE policy.schemaname = 'public' AND policy.tablename = 'projects'
        AND policy.cmd IN ('SELECT','ALL')
        AND (policy.roles @> ARRAY['anon']::name[] OR policy.roles @> ARRAY['public']::name[])
    ) AS anon_applicable_select_policy_count
  FROM pg_class relation
  JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public' AND relation.relname = 'projects' AND relation.relkind IN ('r','p')
), checks AS (
  SELECT 'MIGRATION ABSENT'::text AS check_name,
    migration_state.history_table_exists AND NOT migration_state.recorded
      AND NOT migration_state.snapshot_exists AND NOT migration_state.readiness_exists
      AND to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') IS NULL AS passed,
    format('history_table=%s; recorded=%s; snapshot=%s; readiness=%s', migration_state.history_table_exists,
      migration_state.recorded, migration_state.snapshot_exists, migration_state.readiness_exists) AS detail
  FROM migration_state
  UNION ALL
  SELECT 'REQUIRED OBJECTS',
    to_regclass('public.projects') IS NOT NULL AND to_regclass('public.profiles') IS NOT NULL
      AND to_regclass('public.tasks') IS NOT NULL AND to_regclass('public.project_todos') IS NOT NULL
      AND to_regclass('public.project_updates') IS NOT NULL AND to_regclass('public.crm_clients') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM column_state WHERE NOT present)
      AND has_schema_privilege(current_user, 'public', 'CREATE'),
    format('missing_columns=%s; current_role_can_create_public_functions=%s',
      COALESCE((SELECT string_agg(table_name || '.' || column_name, ', ' ORDER BY table_name, column_name) FROM column_state WHERE NOT present), 'none'),
      has_schema_privilege(current_user, 'public', 'CREATE'))
  UNION ALL
  SELECT 'EXPECTED SIGNATURES',
    NOT EXISTS (SELECT 1 FROM function_state WHERE must_exist AND oid IS NULL)
      AND NOT EXISTS (SELECT 1 FROM function_state WHERE must_be_absent AND oid IS NOT NULL)
      AND conflicting_overloads.unexpected_count = 0,
    format('missing_required=%s; unexpected_phase1_signatures=%s; genuine_conflicting_overloads=%s',
      COALESCE((SELECT string_agg(signature, ', ' ORDER BY signature) FROM function_state WHERE must_exist AND oid IS NULL), 'none'),
      COALESCE((SELECT string_agg(signature, ', ' ORDER BY signature) FROM function_state WHERE must_be_absent AND oid IS NOT NULL), 'none'),
      conflicting_overloads.unexpected_count)
  FROM conflicting_overloads
  UNION ALL
  SELECT 'CLIENT FACADE STATE',
    to_regprocedure('public.get_crm_client_secure(uuid)') IS NOT NULL
      AND to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') IS NULL,
    format('original=%s; renamed_base=%s',
      to_regprocedure('public.get_crm_client_secure(uuid)') IS NOT NULL,
      to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') IS NOT NULL)
  UNION ALL
  SELECT 'FUNCTION OWNERSHIP', current_user = 'postgres'
      AND NOT EXISTS (SELECT 1 FROM security_functions WHERE oid IS NULL OR function_owner <> 'postgres'),
    format('database_role=%s; non_postgres_or_missing_security_function_owners=%s', current_user,
      COALESCE((SELECT string_agg(signature || '=' || COALESCE(function_owner, 'MISSING'), ', ' ORDER BY signature)
        FROM security_functions WHERE oid IS NULL OR function_owner <> 'postgres'), 'none'))
  UNION ALL
  SELECT 'SECURITY DEFINER/SEARCH_PATH',
    NOT EXISTS (SELECT 1 FROM security_functions WHERE oid IS NULL OR NOT security_definer
      OR NOT (COALESCE(function_config, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[])),
    COALESCE((SELECT string_agg(signature || ':definer=' || COALESCE(security_definer::text,'MISSING')
      || ':config=' || COALESCE(function_config::text,'NULL'), '; ' ORDER BY signature)
      FROM security_functions WHERE oid IS NULL OR NOT security_definer
        OR NOT (COALESCE(function_config, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[])), 'all expected functions are SECURITY DEFINER with pinned search_path')
  UNION ALL
  SELECT 'GRANTS/REVOKES',
    NOT EXISTS (SELECT 1 FROM api_functions WHERE oid IS NULL OR NOT authenticated_execute OR anon_execute),
    COALESCE((SELECT string_agg(signature || ':authenticated=' || authenticated_execute::text
      || ':anon=' || anon_execute::text, '; ' ORDER BY signature)
      FROM api_functions WHERE oid IS NULL OR NOT authenticated_execute OR anon_execute),
      'authenticated EXECUTE granted; anon/PUBLIC effective EXECUTE denied on expected RPCs')
  UNION ALL
  SELECT 'PROJECT TABLE ACCESS MODEL',
    project_access_state.rls_enabled
      AND project_access_state.anon_applicable_select_policy_count = 0
      AND NOT project_access_state.authenticated_table_select
      AND NOT project_access_state.authenticated_column_select,
    format('rls_enabled=%s; anon_table_select=%s; anon_applicable_select_or_all_policies=%s; authenticated_table_select=%s; authenticated_any_column_select=%s',
      project_access_state.rls_enabled, project_access_state.anon_table_select,
      project_access_state.anon_applicable_select_policy_count,
      project_access_state.authenticated_table_select, project_access_state.authenticated_column_select)
  FROM project_access_state
), result_rows AS (
  SELECT check_name || ': ' || CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS summary,
    detail,
    CASE check_name
      WHEN 'CLIENT FACADE STATE' THEN 1
      WHEN 'EXPECTED SIGNATURES' THEN 2
      WHEN 'FUNCTION OWNERSHIP' THEN 3
      WHEN 'GRANTS/REVOKES' THEN 4
      WHEN 'MIGRATION ABSENT' THEN 5
      WHEN 'PROJECT TABLE ACCESS MODEL' THEN 6
      WHEN 'REQUIRED OBJECTS' THEN 7
      WHEN 'SECURITY DEFINER/SEARCH_PATH' THEN 8
      ELSE 99
    END AS sort_order
  FROM checks
  UNION ALL
  SELECT 'UNNECESSARY ANON PROJECT SELECT GRANT: ' ||
      CASE WHEN project_access_state.anon_table_select THEN 'PRESENT' ELSE 'ABSENT' END,
    'Non-blocking least-privilege observation; RLS/policy result is evaluated by PROJECT TABLE ACCESS MODEL.',
    9
  FROM project_access_state
  UNION ALL
  SELECT 'PHASE 1 STAGING PREFLIGHT: ' || CASE WHEN bool_and(passed) THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN bool_and(passed) THEN 'all first-application catalog guards passed' ELSE 'one or more catalog guards failed; do not apply migration' END,
    2
  FROM checks
)
SELECT summary, detail
FROM result_rows
ORDER BY sort_order, summary;
