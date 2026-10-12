-- Read-only catalog preflight for Project Operations Phase 1.
-- This file contains SELECT statements only. Run only against linked staging.

WITH expected_functions(signature, function_name, expected_kind) AS (
  VALUES
    ('public.get_crm_client_secure(uuid)', 'get_crm_client_secure', 'existing façade'),
    ('public.get_crm_client_secure_project_ops_base(uuid)', 'get_crm_client_secure_project_ops_base', 'transition target'),
    ('public.project_operational_snapshot(uuid,uuid)', 'project_operational_snapshot', 'new Phase 1 function'),
    ('public.create_project_secure(jsonb)', 'create_project_secure', 'existing RPC'),
    ('public.update_project_secure(uuid,jsonb)', 'update_project_secure', 'existing RPC'),
    ('public.list_accessible_projects_secure()', 'list_accessible_projects_secure', 'existing RPC'),
    ('public.get_project_detail_secure(uuid)', 'get_project_detail_secure', 'existing RPC'),
    ('public.list_project_command_center(integer,boolean,integer)', 'list_project_command_center', 'existing RPC'),
    ('public.get_project_operational_summary(uuid)', 'get_project_operational_summary', 'existing RPC'),
    ('public.get_project_health(uuid)', 'get_project_health', 'existing RPC'),
    ('public.get_project_completion_readiness(uuid)', 'get_project_completion_readiness', 'new Phase 1 RPC'),
    ('public.change_project_status(uuid,text)', 'change_project_status', 'existing RPC'),
    ('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)', 'create_project_from_won_deal', 'legacy RPC to revoke'),
    ('public.can_access_project(uuid,uuid)', 'can_access_project', 'authorization dependency'),
    ('public.is_project_portfolio_admin(uuid)', 'is_project_portfolio_admin', 'authorization dependency'),
    ('public.task_dependency_blocked(uuid)', 'task_dependency_blocked', 'Phase B dependency dependency'),
    ('public.can_view_business_financials(uuid)', 'can_view_business_financials', 'financial authorization dependency'),
    ('public.can_access_task(uuid,uuid)', 'can_access_task', 'Task privacy dependency'),
    ('public.list_project_updates_secure(uuid)', 'list_project_updates_secure', 'Project detail dependency'),
    ('public.list_project_todos_secure(uuid)', 'list_project_todos_secure', 'Project detail dependency'),
    ('public.list_project_shared_attachments(uuid)', 'list_project_shared_attachments', 'Project detail dependency')
), resolved_functions AS (
  SELECT
    expected.signature,
    expected.function_name,
    expected.expected_kind,
    proc.oid IS NOT NULL AS present,
    owner_role.rolname AS function_owner,
    proc.prosecdef AS security_definer,
    proc.proconfig AS function_config,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE has_function_privilege('authenticated', proc.oid, 'EXECUTE') END AS authenticated_can_execute,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE has_function_privilege('anon', proc.oid, 'EXECUTE') END AS anon_can_execute
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
), named_phase1_functions AS (
  SELECT namespace.nspname AS schema_name, proc.proname AS function_name,
    pg_get_function_identity_arguments(proc.oid) AS identity_arguments,
    owner_role.rolname AS function_owner, proc.prosecdef AS security_definer, proc.proconfig AS function_config
  FROM pg_proc proc
  JOIN pg_namespace namespace ON namespace.oid = proc.pronamespace
  JOIN pg_roles owner_role ON owner_role.oid = proc.proowner
  WHERE namespace.nspname = 'public'
    AND proc.proname IN (
      'project_operational_snapshot', 'get_project_completion_readiness',
      'get_crm_client_secure', 'get_crm_client_secure_project_ops_base',
      'create_project_secure', 'update_project_secure', 'list_accessible_projects_secure',
      'get_project_detail_secure', 'list_project_command_center', 'get_project_operational_summary',
      'get_project_health', 'change_project_status'
    )
)
SELECT jsonb_pretty(jsonb_build_object(
  'database_role', current_user,
  'migration_history_table_exists', to_regclass('supabase_migrations.schema_migrations') IS NOT NULL,
  'migration_recorded', EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261002090000'
  ),
  'client_facade_transition', jsonb_build_object(
    'original_get_crm_client_secure_exists', to_regprocedure('public.get_crm_client_secure(uuid)') IS NOT NULL,
    'renamed_base_exists', to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') IS NOT NULL,
    'first_application_state',
      to_regprocedure('public.get_crm_client_secure(uuid)') IS NOT NULL
      AND to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') IS NULL
  ),
  'phase1_signatures_already_present', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('function', function_name, 'arguments', identity_arguments,
      'owner', function_owner, 'security_definer', security_definer, 'config', function_config)
    ORDER BY function_name, identity_arguments)
    FROM named_phase1_functions
    WHERE function_name IN ('project_operational_snapshot','get_project_completion_readiness')
  ), '[]'::jsonb),
  'expected_functions', (SELECT jsonb_agg(to_jsonb(resolved_functions) ORDER BY signature) FROM resolved_functions),
  'same_name_signatures', (SELECT jsonb_agg(to_jsonb(named_phase1_functions) ORDER BY function_name, identity_arguments) FROM named_phase1_functions),
  'missing_tables', COALESCE((
    SELECT jsonb_agg(required.table_name ORDER BY required.table_name)
    FROM (VALUES ('projects'),('profiles'),('tasks'),('project_todos'),('project_updates'),('crm_clients')) required(table_name)
    WHERE to_regclass('public.' || required.table_name) IS NULL
  ), '[]'::jsonb),
  'missing_columns', COALESCE((
    SELECT jsonb_agg(table_name || '.' || column_name ORDER BY table_name, column_name)
    FROM column_state WHERE NOT present
  ), '[]'::jsonb),
  'project_table_privileges', jsonb_build_object(
    'authenticated_select', has_table_privilege('authenticated','public.projects','SELECT'),
    'anon_select', has_table_privilege('anon','public.projects','SELECT')
  )
)) AS phase1_staging_catalog_preflight;

-- Effective function grants and security metadata for the existing façade and
-- privileged RPCs; the migration's post-state can be compared to this baseline.
SELECT
  proc.proname AS function_name,
  pg_get_function_identity_arguments(proc.oid) AS identity_arguments,
  owner_role.rolname AS function_owner,
  proc.prosecdef AS security_definer,
  proc.proconfig AS function_config,
  has_function_privilege('authenticated', proc.oid, 'EXECUTE') AS authenticated_can_execute,
  has_function_privilege('anon', proc.oid, 'EXECUTE') AS anon_can_execute,
  proc.proacl AS function_acl
FROM pg_proc proc
JOIN pg_namespace namespace ON namespace.oid = proc.pronamespace
JOIN pg_roles owner_role ON owner_role.oid = proc.proowner
WHERE namespace.nspname = 'public'
  AND proc.proname IN (
    'get_crm_client_secure', 'create_project_secure', 'update_project_secure',
    'list_accessible_projects_secure', 'get_project_detail_secure',
    'list_project_command_center', 'get_project_operational_summary',
    'get_project_health', 'change_project_status', 'create_project_from_won_deal'
  )
ORDER BY proc.proname, pg_get_function_identity_arguments(proc.oid);
