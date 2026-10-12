-- Final S3 staging preflight. Catalog/read-only inspection only; no business rows.
WITH
required_history(version) AS (
  VALUES
    ('20260928120000'), ('20260930100000'), ('20260930101000'),
    ('20260930102000'), ('20260930103000'), ('20260930104000'),
    ('20260930105000'), ('20260930106000'), ('20261001090000'),
    ('20261001100000'), ('20261002090000'), ('20261005100000')
), history_state AS (
  SELECT bool_and(EXISTS (
           SELECT 1 FROM supabase_migrations.schema_migrations sm
           WHERE sm.version = h.version
         )) AS predecessors_recorded,
         NOT EXISTS (
           SELECT 1 FROM supabase_migrations.schema_migrations sm
           WHERE sm.version = '20261005110000'
         ) AS s3_not_recorded
  FROM required_history h
), login_table AS (
  SELECT c.oid, c.relowner, c.relacl, c.relrowsecurity, c.relforcerowsecurity,
         owner_role.rolname AS owner_name
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = c.relowner
  WHERE n.nspname = 'public' AND c.relname = 'login_attempts' AND c.relkind IN ('r','p')
), login_columns AS (
  SELECT
    count(*) FILTER (WHERE a.attname = 'email' AND a.atttypid = 'text'::regtype) = 1 AS email_ok,
    count(*) FILTER (WHERE a.attname = 'attempts' AND a.atttypid = 'integer'::regtype) = 1 AS attempts_ok,
    count(*) FILTER (WHERE a.attname = 'locked_until' AND a.atttypid = 'timestamp with time zone'::regtype) = 1 AS locked_until_ok
  FROM login_table t
  JOIN pg_catalog.pg_attribute a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
), login_policies AS (
  SELECT
    count(*) FILTER (WHERE policyname = 'Anyone can read login attempts'
      AND cmd = 'SELECT' AND 'public' = ANY(roles) AND COALESCE(qual, '') IN ('true','(true)')) = 1 AS legacy_policy_expected,
    count(*) FILTER (WHERE cmd IN ('SELECT','ALL')
      AND policyname <> 'Anyone can read login attempts') AS unreviewed_read_policy_count,
    count(*) AS policy_count,
    COALESCE(jsonb_agg(jsonb_build_object(
      'name', policyname, 'roles', roles, 'command', cmd,
      'using', qual, 'with_check', with_check
    ) ORDER BY policyname), '[]'::jsonb) AS policy_details
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public' AND tablename = 'login_attempts'
), login_acl AS (
  SELECT
    COALESCE(pg_catalog.has_table_privilege('anon', t.oid, 'SELECT'), false) AS anon_select,
    COALESCE(pg_catalog.has_table_privilege('authenticated', t.oid, 'SELECT'), false) AS authenticated_select,
    COALESCE(pg_catalog.has_table_privilege('service_role', t.oid, 'SELECT'), false) AS service_role_select,
    COALESCE(pg_catalog.has_table_privilege('service_role', t.oid, 'INSERT'), false) AS service_role_insert,
    COALESCE(pg_catalog.has_table_privilege('service_role', t.oid, 'UPDATE'), false) AS service_role_update,
    COALESCE(pg_catalog.has_table_privilege('service_role', t.oid, 'DELETE'), false) AS service_role_delete,
    COALESCE(pg_catalog.has_table_privilege('anon', t.oid, 'INSERT'), false) AS anon_insert,
    COALESCE(pg_catalog.has_table_privilege('anon', t.oid, 'UPDATE'), false) AS anon_update,
    COALESCE(pg_catalog.has_table_privilege('anon', t.oid, 'DELETE'), false) AS anon_delete,
    COALESCE(pg_catalog.has_table_privilege('authenticated', t.oid, 'INSERT'), false) AS authenticated_insert,
    COALESCE(pg_catalog.has_table_privilege('authenticated', t.oid, 'UPDATE'), false) AS authenticated_update,
    COALESCE(pg_catalog.has_table_privilege('authenticated', t.oid, 'DELETE'), false) AS authenticated_delete,
    COALESCE(pg_catalog.has_any_column_privilege('anon', t.oid, 'INSERT'), false) AS anon_column_insert,
    COALESCE(pg_catalog.has_any_column_privilege('anon', t.oid, 'UPDATE'), false) AS anon_column_update,
    COALESCE(pg_catalog.has_any_column_privilege('authenticated', t.oid, 'INSERT'), false) AS authenticated_column_insert,
    COALESCE(pg_catalog.has_any_column_privilege('authenticated', t.oid, 'UPDATE'), false) AS authenticated_column_update,
    COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'grantee', COALESCE(r.rolname, CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE 'UNKNOWN' END),
      'privilege', a.privilege_type, 'grantable', a.is_grantable
    ) ORDER BY COALESCE(r.rolname, 'PUBLIC'), a.privilege_type)
      FROM pg_catalog.aclexplode(COALESCE(t.relacl, pg_catalog.acldefault('r', t.relowner))) a
      LEFT JOIN pg_catalog.pg_roles r ON r.oid = a.grantee), '[]'::jsonb) AS direct_table_acl
  FROM (VALUES (1)) AS seed(dummy)
  LEFT JOIN login_table t ON true
), relevant_column_acl AS (
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'column', a.attname,
    'grantee', COALESCE(r.rolname, CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE 'UNKNOWN' END),
    'privilege', x.privilege_type, 'grantable', x.is_grantable
  ) ORDER BY a.attname, COALESCE(r.rolname, 'PUBLIC'), x.privilege_type), '[]'::jsonb) AS direct_column_acl
  FROM login_table t
  JOIN pg_catalog.pg_attribute a ON a.attrelid = t.oid
    AND a.attname IN ('email','attempts','locked_until') AND a.attnum > 0 AND NOT a.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
  LEFT JOIN pg_catalog.pg_roles r ON r.oid = x.grantee
), function_targets(signature, function_name) AS (
  VALUES
    ('public.record_failed_login(text)', 'record_failed_login'),
    ('public.reset_login_lockout(text)', 'reset_login_lockout'),
    ('public.delete_user(uuid)', 'delete_user'),
    ('public.crm_client_dto(public.crm_clients)', 'crm_client_dto'),
    ('public.list_accessible_project_profiles()', 'list_accessible_project_profiles')
), functions AS (
  SELECT ft.signature, ft.function_name, p.oid, p.proowner, owner_role.rolname AS owner_name,
         p.prosecdef, p.proconfig, language.lanname,
         pg_catalog.pg_get_function_result(p.oid) AS result_type,
         COALESCE(pg_catalog.pg_get_functiondef(p.oid), '') AS definition,
         COALESCE(pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'), false) AS anon_effective_execute,
         COALESCE(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'), false) AS authenticated_effective_execute,
         COALESCE(pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE'), false) AS service_role_effective_execute,
         COALESCE((SELECT bool_or(x.grantee = 0 AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x), false) AS public_direct_execute,
         COALESCE((SELECT bool_or(x.grantee = r.oid AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
           JOIN pg_catalog.pg_roles r ON r.oid = x.grantee WHERE r.rolname = 'anon'), false) AS anon_direct_execute,
         COALESCE((SELECT bool_or(x.grantee = r.oid AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
           JOIN pg_catalog.pg_roles r ON r.oid = x.grantee WHERE r.rolname = 'authenticated'), false) AS authenticated_direct_execute,
         COALESCE((SELECT bool_or(x.grantee = r.oid AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
           JOIN pg_catalog.pg_roles r ON r.oid = x.grantee WHERE r.rolname = 'service_role'), false) AS service_role_direct_execute,
         COALESCE(array_to_string(p.proconfig, ';'), 'UNSET') AS search_path,
         p.proargnames
  FROM function_targets ft
  LEFT JOIN pg_catalog.pg_proc p ON p.oid = to_regprocedure(ft.signature) AND p.prokind = 'f'
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = p.proowner
  LEFT JOIN pg_catalog.pg_language language ON language.oid = p.prolang
), s3_function_checks AS (
  SELECT
    count(*) = 3 AND bool_and(oid IS NOT NULL AND result_type = 'void' AND lanname = 'plpgsql'
      AND prosecdef AND owner_name = 'postgres') AS signatures_security_owner_valid,
    bool_and(CASE function_name
      WHEN 'record_failed_login' THEN definition ILIKE '%INSERT INTO public.login_attempts%'
        AND definition ILIKE '%ON CONFLICT%' AND definition ILIKE '%locked_until%'
      WHEN 'reset_login_lockout' THEN definition ILIKE '%UPDATE public.login_attempts%'
        AND proargnames @> ARRAY['user_email']::text[]
      WHEN 'delete_user' THEN definition ILIKE '%auth.uid()%'
        AND definition ILIKE '%ADMIN%' AND definition ILIKE '%is_active%'
      ELSE false END) AS expected_body_markers,
    COALESCE(jsonb_agg(jsonb_build_object(
      'signature', signature, 'owner', owner_name, 'language', lanname,
      'returns', result_type, 'security_definer', prosecdef, 'search_path', search_path,
      'public_direct_execute', public_direct_execute,
      'anon_direct_execute', anon_direct_execute,
      'anon_effective_execute', anon_effective_execute,
      'authenticated_direct_execute', authenticated_direct_execute,
      'authenticated_effective_execute', authenticated_effective_execute,
      'service_role_direct_execute', service_role_direct_execute,
      'service_role_effective_execute', service_role_effective_execute
    ) ORDER BY function_name), '[]'::jsonb) AS current_security_properties
  FROM functions WHERE function_name IN ('record_failed_login','reset_login_lockout','delete_user')
), phase1_expected(signature, access_mode, expected_result) AS (
  VALUES
    ('public.get_crm_client_secure(uuid)','authenticated','jsonb'),
    ('public.get_crm_client_secure_project_ops_base(uuid)','internal','jsonb'),
    ('public.project_operational_snapshot(uuid,uuid)','internal','jsonb'),
    ('public.create_project_secure(jsonb)','authenticated','jsonb'),
    ('public.update_project_secure(uuid,jsonb)','authenticated','jsonb'),
    ('public.list_accessible_projects_secure()','authenticated','SETOF jsonb'),
    ('public.get_project_detail_secure(uuid)','authenticated','jsonb'),
    ('public.list_project_command_center(integer,boolean,integer)','authenticated','SETOF jsonb'),
    ('public.get_project_operational_summary(uuid)','authenticated','jsonb'),
    ('public.get_project_health(uuid)','authenticated','jsonb'),
    ('public.get_project_completion_readiness(uuid)','authenticated','jsonb'),
    ('public.change_project_status(uuid,text)','authenticated','jsonb')
), phase1_resolved AS (
  SELECT e.signature, e.access_mode, e.expected_result, p.oid, owner_role.rolname AS owner_name,
         p.prosecdef, p.proconfig, pg_catalog.pg_get_function_result(p.oid) AS result_type,
         COALESCE(pg_catalog.pg_get_functiondef(p.oid), '') AS definition,
         COALESCE(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'), false) AS auth_execute,
         COALESCE(pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'), false) AS anon_execute,
         COALESCE((SELECT bool_or(x.grantee = 0 AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x), false) AS public_execute
  FROM phase1_expected e
  LEFT JOIN pg_catalog.pg_proc p ON p.oid = to_regprocedure(e.signature)
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = p.proowner
), phase1_state AS (
  SELECT count(*) = 12 AND bool_and(oid IS NOT NULL AND result_type = expected_result
      AND owner_name = 'postgres' AND prosecdef
      AND COALESCE(proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[]
      AND NOT anon_execute AND NOT public_execute
      AND CASE WHEN access_mode = 'authenticated' THEN auth_execute ELSE NOT auth_execute END
    )
    AND EXISTS (SELECT 1 FROM phase1_resolved WHERE signature='public.get_crm_client_secure(uuid)'
      AND definition ILIKE '%project_operational_snapshot%' AND definition ILIKE '%can_access_project%')
    AND EXISTS (SELECT 1 FROM phase1_resolved WHERE signature='public.get_project_completion_readiness(uuid)'
      AND definition ILIKE '%NO_TASKS%')
    AND EXISTS (SELECT 1 FROM phase1_resolved WHERE signature='public.get_project_operational_summary(uuid)'
      AND definition ILIKE '%project_operational_snapshot%')
    AND EXISTS (SELECT 1 FROM phase1_resolved WHERE signature='public.get_project_health(uuid)'
      AND definition ILIKE '%project_operational_snapshot%') AS phase1_rpc_state_valid
  FROM phase1_resolved
), client_profile_state AS (
  SELECT
    COALESCE((SELECT oid IS NOT NULL AND NOT authenticated_effective_execute
       AND NOT anon_effective_execute AND NOT public_direct_execute
       FROM functions WHERE function_name = 'crm_client_dto'), false) AS client_dto_internal_only,
    COALESCE((SELECT oid IS NOT NULL AND owner_name = 'postgres' AND prosecdef
       AND COALESCE(proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[]
       AND authenticated_effective_execute AND authenticated_direct_execute
       AND NOT anon_effective_execute AND NOT anon_direct_execute AND NOT public_direct_execute
       AND definition ILIKE '%emp_index%NULLS LAST%' AND definition ILIKE '%full_name%'
       FROM functions WHERE function_name = 'list_accessible_project_profiles'), false) AS profile_directory_acl_and_order_valid
), login_policy_summary AS (
  SELECT p.*, (t.relrowsecurity IS TRUE) AS rls_enabled,
         t.relforcerowsecurity AS rls_forced,
         to_jsonb(a) AS effective_and_direct_grants,
         to_jsonb(c) AS relevant_column_grants
  FROM login_policies p
  CROSS JOIN login_acl a
  CROSS JOIN relevant_column_acl c
  LEFT JOIN login_table t ON true
), checks AS (
  SELECT 'MIGRATION_PREDECESSOR_HISTORY_COMPLETE' AS name,
         h.predecessors_recorded AND h.s3_not_recorded AS passed
  FROM history_state h
  UNION ALL
  SELECT 'LOGIN_ATTEMPTS_SCHEMA_RLS_POLICY_BASELINE',
         EXISTS (SELECT 1 FROM login_table)
         AND (SELECT email_ok AND attempts_ok AND locked_until_ok FROM login_columns)
         AND (SELECT rls_enabled AND legacy_policy_expected AND unreviewed_read_policy_count = 0 FROM login_policy_summary)
  UNION ALL
  SELECT 'SERVICE_ROLE_LOGIN_ATTEMPTS_ACCESS_RETAINED',
         (SELECT service_role_select AND service_role_insert AND service_role_update AND service_role_delete FROM login_acl)
  UNION ALL
  SELECT 'AUTH_SECURITY_FUNCTION_SIGNATURES_OWNERSHIP_SECURITY', signatures_security_owner_valid
  FROM s3_function_checks
  UNION ALL
  SELECT 'AUTH_SECURITY_FUNCTION_BODY_PRECONDITIONS', expected_body_markers
  FROM s3_function_checks
  UNION ALL
  SELECT 'PHASE1_PROJECT_RLS_AND_DIRECT_WRITE_BOUNDARY',
         EXISTS (SELECT 1 FROM pg_catalog.pg_class c
           JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname='public' AND c.relname='projects' AND c.relrowsecurity)
         AND NOT pg_catalog.has_table_privilege('authenticated','public.projects','INSERT')
         AND NOT pg_catalog.has_table_privilege('authenticated','public.projects','UPDATE')
         AND NOT pg_catalog.has_table_privilege('authenticated','public.projects','DELETE')
         AND to_regprocedure('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)') IS NOT NULL
         AND NOT pg_catalog.has_function_privilege('authenticated','public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)','EXECUTE')
         AND NOT pg_catalog.has_function_privilege('anon','public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)','EXECUTE')
  UNION ALL
  SELECT 'CLIENT_DTO_ACL_CORRECTION_STILL_VALID', client_dto_internal_only
  FROM client_profile_state
  UNION ALL
  SELECT 'PROFILE_DIRECTORY_ACL_AND_ORDERING_STILL_VALID', profile_directory_acl_and_order_valid
  FROM client_profile_state
  UNION ALL
  SELECT 'PHASE1_RPC_CATALOG_AND_ACL_STILL_VALID', phase1_rpc_state_valid
  FROM phase1_state
), summary AS (
  SELECT bool_and(passed) AS passed,
         COALESCE(jsonb_agg(name ORDER BY name) FILTER (WHERE NOT passed), '[]'::jsonb) AS failed_predicates,
         COALESCE(jsonb_agg(jsonb_build_object('name', name, 'pass', passed) ORDER BY name), '[]'::jsonb) AS checks
  FROM checks
)
SELECT jsonb_build_object(
  'S3_STAGING_PREFLIGHT', CASE WHEN summary.passed THEN 'PASS' ELSE 'FAIL' END,
  'FAILED_PREDICATES', summary.failed_predicates,
  'CHECKS', summary.checks,
  'MIGRATION_HISTORY', jsonb_build_object(
    'required_predecessors_recorded', history_state.predecessors_recorded,
    's3_not_recorded', history_state.s3_not_recorded,
    'versions_checked', (SELECT jsonb_agg(version ORDER BY version) FROM required_history)
  ),
  'LOGIN_ATTEMPTS', jsonb_build_object(
    'exists', EXISTS (SELECT 1 FROM login_table),
    'rls_enabled', COALESCE(login_policy_summary.rls_enabled, false),
    'rls_forced', login_policy_summary.rls_forced,
    'columns', (SELECT to_jsonb(login_columns) FROM login_columns),
    'policies', login_policy_summary.policy_details,
    'unreviewed_select_or_all_policy_count', login_policy_summary.unreviewed_read_policy_count,
    'table_grants', login_policy_summary.effective_and_direct_grants,
    'relevant_column_acl', login_policy_summary.relevant_column_grants
  ),
  'S3_FUNCTIONS', s3_function_checks.current_security_properties,
  'CLIENT_DTO_INTERNAL_ONLY', client_profile_state.client_dto_internal_only,
  'PROFILE_DIRECTORY_ACL_AND_ORDERING_VALID', client_profile_state.profile_directory_acl_and_order_valid,
  'PHASE1_RPC_CATALOG_VALID', phase1_state.phase1_rpc_state_valid
) AS s3_staging_preflight
FROM summary CROSS JOIN history_state CROSS JOIN login_policy_summary
CROSS JOIN s3_function_checks CROSS JOIN client_profile_state CROSS JOIN phase1_state;
