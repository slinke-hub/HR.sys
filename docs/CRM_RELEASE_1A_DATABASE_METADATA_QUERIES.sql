-- CRM Release 1A read-only catalog evidence queries.
-- Run separately against staging and Production only with the approved
-- read-only database role and the correct project selected out-of-band.
-- Expected staging project ref: jcfyyxsuspukcmybyhjj
-- This file contains no connection string, token, secret, or business-row query.
-- All result sets are catalog metadata only. Do not substitute another project.

BEGIN READ ONLY;

-- 1. Confirm this connection's database and read-only role identity.
SELECT current_database() AS database_name,
       current_user AS database_role,
       current_setting('transaction_read_only') AS transaction_read_only;

-- 2. Triggers on the task, task-list, and CRM-deal tables. pg_get_triggerdef
-- gives timing/events/row mode; the joined function fields identify the exact
-- trigger function, owner, SECURITY DEFINER flag, and configured search path.
SELECT ns.nspname AS table_schema,
       tbl.relname AS table_name,
       trg.tgname AS trigger_name,
       CASE trg.tgenabled
         WHEN 'O' THEN 'enabled: origin/local'
         WHEN 'D' THEN 'disabled'
         WHEN 'R' THEN 'enabled: replica'
         WHEN 'A' THEN 'enabled: always'
         ELSE 'unknown: ' || trg.tgenabled::text
       END AS enabled_state,
       pg_get_triggerdef(trg.oid, true) AS trigger_definition,
       fn.oid::regprocedure::text AS function_signature,
       owner_role.rolname AS function_owner,
       fn.prosecdef AS security_definer,
       COALESCE((SELECT replace(cfg, 'search_path=', '')
                 FROM unnest(fn.proconfig) AS setting(cfg)
                 WHERE cfg LIKE 'search_path=%' LIMIT 1), '(not pinned)') AS configured_search_path
FROM pg_trigger trg
JOIN pg_class tbl ON tbl.oid = trg.tgrelid
JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
JOIN pg_proc fn ON fn.oid = trg.tgfoid
JOIN pg_roles owner_role ON owner_role.oid = fn.proowner
WHERE ns.nspname = 'public'
  AND tbl.relname = ANY (ARRAY['tasks', 'task_lists', 'crm_deals'])
  AND NOT trg.tgisinternal
ORDER BY tbl.relname, trg.tgname;

-- 3. Relevant CRM and task RPC/helper signatures, owners, security attributes,
-- configured search paths, and effective EXECUTE privilege for anon/authenticated.
WITH target_functions(name) AS (
  VALUES
    ('change_crm_deal_stage'), ('start_crm_presentation_approval'),
    ('create_project_from_won_deal_v2'), ('mark_crm_deal_lost'),
    ('start_deal_approval'), ('decide_deal_approval'),
    ('decide_crm_design_task_approval'), ('finalize_crm_deal_approval'),
    ('create_crm_design_task_for_deal'), ('ensure_crm_generated_task'),
    ('change_task_status'), ('create_task_secure'), ('get_my_day'),
    ('can_access_crm'), ('can_view_business_financials'),
    ('can_access_task'), ('can_manage_task'), ('can_execute_task'),
    ('can_add_task_to_list'), ('is_task_department_manager'),
    ('is_crm_approval_admin'), ('enforce_private_task_list_ownership'),
    ('enforce_task_completion_approval'), ('enforce_crm_design_task_completion'),
    ('enforce_deal_workflow_transition'), ('validate_task_department_supervisor'),
    ('sync_crm_design_task_status'), ('record_task_activity'),
    ('notify_task_change'), ('apply_task_creation_defaults')
), selected AS (
  SELECT fn.* FROM pg_proc fn
  JOIN pg_namespace ns ON ns.oid = fn.pronamespace
  JOIN target_functions target ON target.name = fn.proname
  WHERE ns.nspname = 'public'
    AND fn.prokind IN ('f', 'p')
)
SELECT fn.oid::regprocedure::text AS function_signature,
       owner_role.rolname AS function_owner,
       fn.prosecdef AS security_definer,
       COALESCE((SELECT replace(cfg, 'search_path=', '')
                 FROM unnest(fn.proconfig) AS setting(cfg)
                 WHERE cfg LIKE 'search_path=%' LIMIT 1), '(not pinned)') AS configured_search_path,
       role_names.role_name,
       CASE WHEN db_role.oid IS NULL THEN NULL
            ELSE has_function_privilege(db_role.oid, fn.oid, 'EXECUTE')
       END AS effective_execute
FROM selected fn
JOIN pg_roles owner_role ON owner_role.oid = fn.proowner
CROSS JOIN (VALUES ('authenticated'), ('anon')) AS role_names(role_name)
LEFT JOIN pg_roles db_role ON db_role.rolname = role_names.role_name
ORDER BY fn.proname, fn.oid::regprocedure::text, role_names.role_name;

-- 4. Role existence and table RLS/privilege metadata for affected tables.
WITH target_tables(name) AS (
  VALUES
    ('tasks'), ('task_lists'), ('crm_deals'), ('crm_clients'),
    ('crm_deal_attachments'), ('crm_deal_activity'),
    ('crm_deal_approval_steps'), ('crm_design_task_approval_steps'),
    ('crm_generated_tasks'), ('projects'), ('notifications'),
    ('task_attachments'), ('profiles'), ('departments')
), role_names(role_name) AS (VALUES ('authenticated'), ('anon'))
SELECT target.name AS expected_table,
       tbl.oid IS NOT NULL AS table_exists,
       tbl.relrowsecurity AS rls_enabled,
       tbl.relforcerowsecurity AS rls_forced,
       role_names.role_name,
       CASE WHEN db_role.oid IS NULL OR tbl.oid IS NULL THEN NULL
            ELSE has_table_privilege(db_role.oid, tbl.oid, 'SELECT') END AS can_select,
       CASE WHEN db_role.oid IS NULL OR tbl.oid IS NULL THEN NULL
            ELSE has_table_privilege(db_role.oid, tbl.oid, 'INSERT') END AS can_insert,
       CASE WHEN db_role.oid IS NULL OR tbl.oid IS NULL THEN NULL
            ELSE has_table_privilege(db_role.oid, tbl.oid, 'UPDATE') END AS can_update,
       CASE WHEN db_role.oid IS NULL OR tbl.oid IS NULL THEN NULL
            ELSE has_table_privilege(db_role.oid, tbl.oid, 'DELETE') END AS can_delete
FROM target_tables target
LEFT JOIN pg_namespace ns ON ns.nspname = 'public'
LEFT JOIN pg_class tbl ON tbl.relnamespace = ns.oid AND tbl.relname = target.name
CROSS JOIN role_names
LEFT JOIN pg_roles db_role ON db_role.rolname = role_names.role_name
ORDER BY target.name, role_names.role_name;

-- 5. RLS policy metadata. These expressions describe policy logic; no table
-- rows are selected.
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = ANY (ARRAY[
    'tasks', 'task_lists', 'crm_deals', 'crm_clients',
    'crm_deal_attachments', 'crm_deal_activity',
    'crm_deal_approval_steps', 'crm_design_task_approval_steps',
    'crm_generated_tasks', 'projects', 'notifications',
    'task_attachments', 'profiles', 'departments'
  ])
ORDER BY tablename, policyname;

-- 6. Relevant table columns and constraints; no data/default row values.
SELECT table_name, ordinal_position, column_name, data_type,
       udt_schema, udt_name, is_nullable, (column_default IS NOT NULL) AS has_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = ANY (ARRAY[
    'tasks', 'task_lists', 'crm_deals', 'crm_clients',
    'crm_deal_attachments', 'crm_deal_activity',
    'crm_deal_approval_steps', 'crm_design_task_approval_steps',
    'crm_generated_tasks', 'projects', 'notifications',
    'task_attachments', 'profiles', 'departments'
  ])
ORDER BY table_name, ordinal_position;

SELECT tbl.relname AS table_name,
       con.conname AS constraint_name,
       con.contype AS constraint_type,
       pg_get_constraintdef(con.oid, true) AS constraint_definition
FROM pg_constraint con
JOIN pg_class tbl ON tbl.oid = con.conrelid
JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
WHERE ns.nspname = 'public'
  AND tbl.relname = ANY (ARRAY[
    'tasks', 'task_lists', 'crm_deals', 'crm_clients',
    'crm_deal_attachments', 'crm_deal_activity',
    'crm_deal_approval_steps', 'crm_design_task_approval_steps',
    'crm_generated_tasks', 'projects', 'notifications',
    'task_attachments', 'profiles', 'departments'
  ])
ORDER BY tbl.relname, con.conname;

-- 7. Migration-ledger discovery only. If this relation exists and access is
-- authorized, inspect the column list below. If version/name are present,
-- inspect only those identifiers in a separate read-only query:
-- SELECT version, name FROM supabase_migrations.schema_migrations ORDER BY version;
SELECT to_regclass('supabase_migrations.schema_migrations') AS migration_ledger_relation;
SELECT table_schema, table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'supabase_migrations'
  AND table_name = 'schema_migrations'
ORDER BY ordinal_position;

ROLLBACK;
