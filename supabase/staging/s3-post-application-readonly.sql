-- S3 post-application verification. Catalog SELECT statements only.
WITH login_table AS (
  SELECT c.oid, c.relowner, c.relacl, c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'login_attempts' AND c.relkind IN ('r','p')
), login_acl AS (
  SELECT
    COALESCE(pg_catalog.has_table_privilege('anon', t.oid, 'SELECT'), false) AS anon_select,
    COALESCE(pg_catalog.has_table_privilege('authenticated', t.oid, 'SELECT'), false) AS auth_select,
    COALESCE(pg_catalog.has_table_privilege('anon', t.oid, 'INSERT'), false) AS anon_insert,
    COALESCE(pg_catalog.has_table_privilege('anon', t.oid, 'UPDATE'), false) AS anon_update,
    COALESCE(pg_catalog.has_table_privilege('anon', t.oid, 'DELETE'), false) AS anon_delete,
    COALESCE(pg_catalog.has_table_privilege('authenticated', t.oid, 'INSERT'), false) AS auth_insert,
    COALESCE(pg_catalog.has_table_privilege('authenticated', t.oid, 'UPDATE'), false) AS auth_update,
    COALESCE(pg_catalog.has_table_privilege('authenticated', t.oid, 'DELETE'), false) AS auth_delete,
    COALESCE(pg_catalog.has_any_column_privilege('anon', t.oid, 'SELECT'), false) AS anon_column_select,
    COALESCE(pg_catalog.has_any_column_privilege('authenticated', t.oid, 'SELECT'), false) AS auth_column_select,
    COALESCE(pg_catalog.has_any_column_privilege('anon', t.oid, 'INSERT'), false) AS anon_column_insert,
    COALESCE(pg_catalog.has_any_column_privilege('anon', t.oid, 'UPDATE'), false) AS anon_column_update,
    COALESCE(pg_catalog.has_any_column_privilege('authenticated', t.oid, 'INSERT'), false) AS auth_column_insert,
    COALESCE(pg_catalog.has_any_column_privilege('authenticated', t.oid, 'UPDATE'), false) AS auth_column_update,
    COALESCE(pg_catalog.has_table_privilege('service_role', t.oid, 'SELECT'), false) AS service_select,
    COALESCE(pg_catalog.has_table_privilege('service_role', t.oid, 'INSERT'), false) AS service_insert,
    COALESCE(pg_catalog.has_table_privilege('service_role', t.oid, 'UPDATE'), false) AS service_update,
    COALESCE(pg_catalog.has_table_privilege('service_role', t.oid, 'DELETE'), false) AS service_delete,
    COALESCE((SELECT bool_or(x.grantee = 0 AND x.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE'))
      FROM pg_catalog.aclexplode(COALESCE(t.relacl, pg_catalog.acldefault('r', t.relowner))) x), false) AS public_direct_access,
    COALESCE((SELECT bool_or(x.grantee = r.oid AND x.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE'))
      FROM pg_catalog.aclexplode(COALESCE(t.relacl, pg_catalog.acldefault('r', t.relowner))) x
      JOIN pg_catalog.pg_roles r ON r.oid = x.grantee WHERE r.rolname = 'anon'), false) AS anon_direct_access,
    COALESCE((SELECT bool_or(x.grantee = r.oid AND x.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE'))
      FROM pg_catalog.aclexplode(COALESCE(t.relacl, pg_catalog.acldefault('r', t.relowner))) x
      JOIN pg_catalog.pg_roles r ON r.oid = x.grantee WHERE r.rolname = 'authenticated'), false) AS auth_direct_access
  FROM login_table t
), login_policies AS (
  SELECT count(*) FILTER (WHERE cmd IN ('SELECT','ALL')) AS read_policy_count,
         count(*) FILTER (WHERE policyname = 'Anyone can read login attempts') AS legacy_policy_count
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public' AND tablename = 'login_attempts'
), fn_targets(signature, short_name) AS (
  VALUES ('public.record_failed_login(text)', 'record_failed_login'),
         ('public.reset_login_lockout(text)', 'reset_login_lockout'),
         ('public.delete_user(uuid)', 'delete_user'),
         ('public.crm_client_dto(public.crm_clients)', 'crm_client_dto'),
         ('public.list_accessible_project_profiles()', 'profile_directory'),
         ('public.get_crm_client_secure(uuid)', 'client_facade'),
         ('public.get_crm_client_secure_project_ops_base(uuid)', 'client_base'),
         ('public.project_operational_snapshot(uuid,uuid)', 'project_snapshot'),
         ('public.create_project_secure(jsonb)', 'create_project'),
         ('public.update_project_secure(uuid,jsonb)', 'update_project'),
         ('public.list_accessible_projects_secure()', 'list_projects'),
         ('public.get_project_detail_secure(uuid)', 'project_detail'),
         ('public.list_project_command_center(integer,boolean,integer)', 'command_center'),
         ('public.get_project_operational_summary(uuid)', 'operational_summary'),
         ('public.get_project_health(uuid)', 'project_health'),
         ('public.get_project_completion_readiness(uuid)', 'completion_readiness'),
         ('public.change_project_status(uuid,text)', 'change_project_status')
), fn_state AS (
  SELECT t.signature, t.short_name, p.oid, p.proowner, owner_role.rolname AS owner_name,
         p.prosecdef, p.proconfig, COALESCE(pg_catalog.pg_get_functiondef(p.oid), '') AS definition,
         pg_catalog.pg_get_function_result(p.oid) AS result_type,
         COALESCE(pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'), false) AS anon_exec,
         COALESCE(pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'), false) AS auth_exec,
         COALESCE(pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE'), false) AS service_exec,
         COALESCE((SELECT bool_or(x.grantee = 0 AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x), false) AS public_direct_exec,
         COALESCE((SELECT bool_or(x.grantee = r.oid AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
           JOIN pg_catalog.pg_roles r ON r.oid = x.grantee WHERE r.rolname = 'anon'), false) AS anon_direct_exec,
         COALESCE((SELECT bool_or(x.grantee = r.oid AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
           JOIN pg_catalog.pg_roles r ON r.oid = x.grantee WHERE r.rolname = 'authenticated'), false) AS auth_direct_exec,
         COALESCE((SELECT bool_or(x.grantee = r.oid AND x.privilege_type = 'EXECUTE')
           FROM pg_catalog.aclexplode(COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))) x
           JOIN pg_catalog.pg_roles r ON r.oid = x.grantee WHERE r.rolname = 'service_role'), false) AS service_direct_exec
  FROM fn_targets t
  LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(t.signature) AND p.prokind = 'f'
  LEFT JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = p.proowner
), phase1_targets(signature, auth_expected, expected_result) AS (
  VALUES ('public.get_crm_client_secure(uuid)', true, 'jsonb'),
    ('public.get_crm_client_secure_project_ops_base(uuid)', false, 'jsonb'),
    ('public.project_operational_snapshot(uuid,uuid)', false, 'jsonb'),
    ('public.create_project_secure(jsonb)', true, 'jsonb'), ('public.update_project_secure(uuid,jsonb)', true, 'jsonb'),
    ('public.list_accessible_projects_secure()', true, 'SETOF jsonb'), ('public.get_project_detail_secure(uuid)', true, 'jsonb'),
    ('public.list_project_command_center(integer,boolean,integer)', true, 'SETOF jsonb'),
    ('public.get_project_operational_summary(uuid)', true, 'jsonb'), ('public.get_project_health(uuid)', true, 'jsonb'),
    ('public.get_project_completion_readiness(uuid)', true, 'jsonb'), ('public.change_project_status(uuid,text)', true, 'jsonb')
), phase1_state AS (
  SELECT count(*) = 12 AND bool_and(f.oid IS NOT NULL AND f.owner_name = 'postgres' AND f.prosecdef
      AND f.result_type = t.expected_result
      AND COALESCE(f.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[]
      AND NOT f.anon_exec AND NOT f.public_direct_exec
      AND CASE WHEN t.auth_expected THEN f.auth_exec ELSE NOT f.auth_exec END) AS valid
  FROM phase1_targets t JOIN fn_state f ON f.signature = t.signature
), checks AS (
  SELECT 'REQUIRED_SIGNATURES_PRESENT' AS name, count(*) = 17 AND count(*) FILTER (WHERE oid IS NOT NULL) = 17 AS passed
  FROM fn_state
  UNION ALL
  SELECT 'LOGIN_ATTEMPTS_EXISTS_RLS' AS name,
    EXISTS (SELECT 1 FROM login_table WHERE relrowsecurity) AS passed
  UNION ALL SELECT 'LOGIN_ATTEMPTS_NO_READ_POLICIES', read_policy_count = 0 AND legacy_policy_count = 0 FROM login_policies
  UNION ALL SELECT 'LOGIN_ATTEMPTS_NO_PUBLIC_ANON_AUTH_TABLE_ACCESS',
    NOT public_direct_access AND NOT anon_direct_access AND NOT auth_direct_access
    AND NOT anon_select AND NOT auth_select AND NOT anon_insert AND NOT anon_update AND NOT anon_delete
    AND NOT auth_insert AND NOT auth_update AND NOT auth_delete
    AND NOT anon_column_select AND NOT auth_column_select AND NOT anon_column_insert AND NOT anon_column_update
    AND NOT auth_column_insert AND NOT auth_column_update
    FROM login_acl
  UNION ALL SELECT 'LOGIN_ATTEMPTS_SERVICE_ROLE_PATH',
    service_select AND service_insert AND service_update AND service_delete FROM login_acl
  UNION ALL SELECT 'RECORD_FAILED_LOGIN_TRUSTED_SERVICE_ONLY',
    f.oid IS NOT NULL AND f.result_type = 'void' AND f.owner_name = 'postgres' AND f.prosecdef
    AND COALESCE(f.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public, pg_temp']::text[]
    AND NOT f.public_direct_exec AND NOT f.anon_direct_exec AND NOT f.auth_direct_exec
    AND NOT f.anon_exec AND NOT f.auth_exec AND f.service_exec AND f.service_direct_exec
    AND f.definition ILIKE '%INSERT INTO public.login_attempts%'
    AND f.definition ILIKE '%ON CONFLICT%' AND f.definition ILIKE '%locked_until%'
    FROM fn_state f WHERE f.signature = 'public.record_failed_login(text)'
  UNION ALL SELECT 'RESET_LOGIN_LOCKOUT_ACTIVE_SELF_OR_ADMIN_AUTH',
    f.oid IS NOT NULL AND f.result_type = 'void' AND f.owner_name = 'postgres' AND f.prosecdef
    AND COALESCE(f.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public, auth, pg_temp']::text[]
    AND NOT f.public_direct_exec AND NOT f.anon_direct_exec
    AND NOT f.anon_exec AND f.auth_exec AND f.auth_direct_exec
    AND f.definition ILIKE '%auth.uid()%' AND f.definition ILIKE '%actor_active IS DISTINCT FROM TRUE%'
    AND f.definition ILIKE '%actor_role = ''ADMIN''%' AND f.definition ILIKE '%actor_email = requested_email%'
    AND f.definition ILIKE '%UPDATE public.login_attempts%'
    FROM fn_state f WHERE f.signature = 'public.reset_login_lockout(text)'
  UNION ALL SELECT 'DELETE_USER_AUTHORIZATION_AND_PATH_PRESERVED',
    f.oid IS NOT NULL AND f.result_type = 'void' AND f.owner_name = 'postgres' AND f.prosecdef
    AND COALESCE(f.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=pg_catalog, public, auth, pg_temp']::text[]
    AND NOT f.public_direct_exec AND NOT f.anon_direct_exec AND NOT f.anon_exec
    AND f.auth_exec AND f.auth_direct_exec
    AND f.definition ILIKE '%auth.uid()%' AND f.definition ILIKE '%is_active%' AND f.definition ILIKE '%ADMIN%'
    FROM fn_state f WHERE f.signature = 'public.delete_user(uuid)'
  UNION ALL SELECT 'CLIENT_DTO_INTERNAL_ACL',
    f.oid IS NOT NULL AND NOT f.public_direct_exec AND NOT f.anon_direct_exec AND NOT f.auth_direct_exec
      AND NOT f.anon_exec AND NOT f.auth_exec
    FROM fn_state f WHERE f.signature = 'public.crm_client_dto(public.crm_clients)'
  UNION ALL SELECT 'PROFILE_DIRECTORY_ACL_AND_ORDER',
    f.oid IS NOT NULL AND f.owner_name = 'postgres' AND f.prosecdef
      AND COALESCE(f.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[]
      AND NOT f.public_direct_exec AND NOT f.anon_direct_exec AND NOT f.anon_exec
      AND f.auth_direct_exec AND f.auth_exec AND f.definition ILIKE '%emp_index%NULLS LAST%'
    FROM fn_state f WHERE f.signature = 'public.list_accessible_project_profiles()'
  UNION ALL SELECT 'PHASE1_CLIENT_FACADE_AND_BASE',
    facade.oid IS NOT NULL AND base.oid IS NOT NULL AND facade.auth_exec AND NOT facade.anon_exec
      AND facade.definition ILIKE '%get_crm_client_secure_project_ops_base%'
      AND NOT base.auth_exec AND NOT base.anon_exec AND NOT base.public_direct_exec
    FROM fn_state facade CROSS JOIN fn_state base
    WHERE facade.signature = 'public.get_crm_client_secure(uuid)'
      AND base.signature = 'public.get_crm_client_secure_project_ops_base(uuid)'
  UNION ALL SELECT 'PHASE1_PROJECT_OPERATIONAL_STATE', valid FROM phase1_state
), summary AS (
  SELECT bool_and(COALESCE(passed, false)) AS passed,
         COALESCE(string_agg(name, ',' ORDER BY name) FILTER (WHERE NOT COALESCE(passed, false)), 'none') AS failures
  FROM checks
)
SELECT 'S3_POST_APPLY_VERIFICATION=' || CASE WHEN summary.passed THEN 'PASS' ELSE 'FAIL' END
       || E'\nFAILED_PREDICATES=' || summary.failures AS s3_post_apply_verification
FROM summary;
