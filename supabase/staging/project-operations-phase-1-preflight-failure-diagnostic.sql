-- Read-only diagnostic for the Phase 1 staging preflight overload and
-- public.projects privilege checks. Catalog metadata only; no business rows.

-- Result set 1: exact unexpected overloads considered by the preflight.
WITH expected(signature, function_name) AS (
  VALUES
    ('public.get_crm_client_secure(uuid)','get_crm_client_secure'),
    ('public.get_crm_client_secure_project_ops_base(uuid)','get_crm_client_secure_project_ops_base'),
    ('public.create_project_secure(jsonb)','create_project_secure'),
    ('public.update_project_secure(uuid,jsonb)','update_project_secure'),
    ('public.list_accessible_projects_secure()','list_accessible_projects_secure'),
    ('public.get_project_detail_secure(uuid)','get_project_detail_secure'),
    ('public.list_project_command_center(integer,boolean,integer)','list_project_command_center'),
    ('public.get_project_operational_summary(uuid)','get_project_operational_summary'),
    ('public.get_project_health(uuid)','get_project_health'),
    ('public.change_project_status(uuid,text)','change_project_status'),
    ('public.project_operational_snapshot(uuid,uuid)','project_operational_snapshot'),
    ('public.get_project_completion_readiness(uuid)','get_project_completion_readiness')
), named_functions AS (
  SELECT namespace.nspname AS schema_name, proc.proname AS function_name,
    pg_get_function_identity_arguments(proc.oid) AS identity_arguments,
    namespace.nspname || '.' || proc.proname || '(' || pg_get_function_identity_arguments(proc.oid) || ')' AS signature,
    proc.oid AS function_oid,
    owner_role.rolname AS function_owner,
    proc.prosecdef AS security_definer,
    proc.proconfig AS function_config,
    has_function_privilege('authenticated', proc.oid, 'EXECUTE') AS authenticated_execute,
    has_function_privilege('anon', proc.oid, 'EXECUTE') AS anon_execute
  FROM pg_proc proc
  JOIN pg_namespace namespace ON namespace.oid = proc.pronamespace
  JOIN pg_roles owner_role ON owner_role.oid = proc.proowner
  WHERE namespace.nspname = 'public'
    AND proc.proname IN (
      'get_crm_client_secure','get_crm_client_secure_project_ops_base',
      'create_project_secure','update_project_secure','list_accessible_projects_secure',
      'get_project_detail_secure','list_project_command_center','get_project_operational_summary',
      'get_project_health','change_project_status','project_operational_snapshot',
      'get_project_completion_readiness'
    )
)
SELECT named_functions.schema_name, named_functions.function_name,
  named_functions.identity_arguments, named_functions.function_owner,
  named_functions.security_definer, named_functions.authenticated_execute,
  named_functions.anon_execute, named_functions.function_config,
  named_functions.signature AS rendered_signature
FROM named_functions
WHERE NOT EXISTS (
  SELECT 1 FROM expected
  WHERE expected.function_name = named_functions.function_name
    AND to_regprocedure(expected.signature) = named_functions.function_oid
)
ORDER BY named_functions.schema_name, named_functions.function_name, named_functions.identity_arguments;

-- Result set 2: projects relation ACL, ownership, and RLS flags.
SELECT namespace.nspname AS schema_name, relation.relname AS table_name,
  owner_role.rolname AS table_owner, relation.relacl AS table_acl,
  relation.relrowsecurity AS rls_enabled, relation.relforcerowsecurity AS rls_forced
FROM pg_class relation
JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
JOIN pg_roles owner_role ON owner_role.oid = relation.relowner
WHERE namespace.nspname = 'public' AND relation.relname = 'projects' AND relation.relkind IN ('r','p');

-- Result set 3: expanded ACL entries, including grants to PUBLIC.
SELECT namespace.nspname AS schema_name, relation.relname AS table_name,
  grantor.rolname AS grantor,
  CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE grantee.rolname END AS grantee,
  acl.privilege_type, acl.is_grantable
FROM pg_class relation
JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
CROSS JOIN LATERAL aclexplode(COALESCE(relation.relacl, acldefault('r', relation.relowner))) acl
LEFT JOIN pg_roles grantor ON grantor.oid = acl.grantor
LEFT JOIN pg_roles grantee ON grantee.oid = acl.grantee
WHERE namespace.nspname = 'public' AND relation.relname = 'projects' AND relation.relkind IN ('r','p')
ORDER BY grantee, acl.privilege_type, grantor;

-- Result set 4: every SELECT or ALL row policy that can affect SELECT, with
-- its target roles and predicate. ALL policies matter for effective SELECT.
SELECT policyname, permissive, roles, cmd, qual AS using_expression,
  with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'projects' AND cmd IN ('SELECT','ALL')
ORDER BY policyname;

-- Result set 5: effective ACL/RLS summary for anon and authenticated.
WITH table_state AS (
  SELECT relation.relrowsecurity AS rls_enabled, relation.relforcerowsecurity AS rls_forced,
    has_table_privilege('anon','public.projects','SELECT') AS anon_select,
    has_table_privilege('authenticated','public.projects','SELECT') AS authenticated_select
  FROM pg_class relation
  JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
  WHERE namespace.nspname = 'public' AND relation.relname = 'projects' AND relation.relkind IN ('r','p')
), policy_state AS (
  SELECT
    count(*) FILTER (WHERE cmd IN ('SELECT','ALL') AND (roles @> ARRAY['anon']::name[] OR roles @> ARRAY['public']::name[]))::integer AS anon_applicable_policy_count,
    count(*) FILTER (WHERE cmd IN ('SELECT','ALL') AND (roles @> ARRAY['authenticated']::name[] OR roles @> ARRAY['public']::name[]))::integer AS authenticated_applicable_policy_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'projects'
)
SELECT role_name,
  CASE role_name WHEN 'anon' THEN table_state.anon_select ELSE table_state.authenticated_select END AS effective_table_select,
  CASE role_name WHEN 'anon' THEN has_any_column_privilege('anon','public.projects','SELECT')
    ELSE has_any_column_privilege('authenticated','public.projects','SELECT') END AS any_column_select,
  table_state.rls_enabled, table_state.rls_forced,
  CASE role_name WHEN 'anon' THEN policy_state.anon_applicable_policy_count
    ELSE policy_state.authenticated_applicable_policy_count END AS applicable_select_or_all_policy_count,
  CASE
    WHEN NOT (CASE role_name WHEN 'anon' THEN table_state.anon_select ELSE table_state.authenticated_select END)
      THEN 'ACL DENIES SELECT'
    WHEN NOT table_state.rls_enabled THEN 'ACL ALLOWS TABLE READ; RLS IS OFF'
    WHEN role_name = 'anon' AND policy_state.anon_applicable_policy_count = 0
      THEN 'ACL ALLOWS SELECT BUT RLS HAS NO ANON/PUBLIC SELECT POLICY; ZERO ROWS ARE VISIBLE'
    WHEN role_name = 'authenticated' AND policy_state.authenticated_applicable_policy_count = 0
      THEN 'ACL ALLOWS SELECT BUT RLS HAS NO AUTHENTICATED/PUBLIC SELECT POLICY; ZERO ROWS ARE VISIBLE'
    ELSE 'AT LEAST ONE SELECT/ALL POLICY APPLIES; REVIEW ITS USING EXPRESSION TO DETERMINE ROW VISIBILITY'
  END AS row_visibility_assessment
FROM table_state CROSS JOIN policy_state
CROSS JOIN (VALUES ('anon'::text),('authenticated'::text)) roles(role_name)
ORDER BY role_name;
