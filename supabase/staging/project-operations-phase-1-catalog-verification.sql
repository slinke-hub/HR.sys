-- Read-only post-application and replay catalog verification for Project
-- Operations Phase 1. Catalog metadata only; no business rows are read.
WITH expected(signature, function_name, expected_result, access_mode) AS (
  VALUES
    ('public.get_crm_client_secure(uuid)','get_crm_client_secure','jsonb','authenticated'),
    ('public.get_crm_client_secure_project_ops_base(uuid)','get_crm_client_secure_project_ops_base','jsonb','internal'),
    ('public.project_operational_snapshot(uuid,uuid)','project_operational_snapshot','jsonb','internal'),
    ('public.create_project_secure(jsonb)','create_project_secure','jsonb','authenticated'),
    ('public.update_project_secure(uuid,jsonb)','update_project_secure','jsonb','authenticated'),
    ('public.list_accessible_projects_secure()','list_accessible_projects_secure','SETOF jsonb','authenticated'),
    ('public.get_project_detail_secure(uuid)','get_project_detail_secure','jsonb','authenticated'),
    ('public.list_project_command_center(integer,boolean,integer)','list_project_command_center','SETOF jsonb','authenticated'),
    ('public.get_project_operational_summary(uuid)','get_project_operational_summary','jsonb','authenticated'),
    ('public.get_project_health(uuid)','get_project_health','jsonb','authenticated'),
    ('public.get_project_completion_readiness(uuid)','get_project_completion_readiness','jsonb','authenticated'),
    ('public.change_project_status(uuid,text)','change_project_status','jsonb','authenticated')
), resolved AS (
  SELECT expected.signature, expected.function_name, expected.expected_result, expected.access_mode,
    proc.oid, owner_role.rolname AS function_owner, proc.prosecdef AS security_definer,
    proc.proconfig AS function_config,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_get_function_result(proc.oid) END AS actual_result,
    CASE WHEN proc.oid IS NULL THEN false ELSE has_function_privilege('authenticated',proc.oid,'EXECUTE') END AS authenticated_execute,
    CASE WHEN proc.oid IS NULL THEN false ELSE has_function_privilege('anon',proc.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN proc.oid IS NULL THEN NULL ELSE pg_get_functiondef(proc.oid) END AS function_definition
  FROM expected
  LEFT JOIN pg_proc proc ON proc.oid=to_regprocedure(expected.signature)
  LEFT JOIN pg_roles owner_role ON owner_role.oid=proc.proowner
), scoped_functions AS (
  SELECT namespace.nspname AS schema_name, proc.proname AS function_name,
    pg_get_function_identity_arguments(proc.oid) AS identity_arguments,
    namespace.nspname || '.' || proc.proname || '(' || pg_get_function_identity_arguments(proc.oid) || ')' AS rendered_identity,
    owner_role.rolname AS function_owner, proc.prosecdef AS security_definer,
    proc.proconfig AS function_config, proc.proacl AS function_acl,
    pg_get_function_result(proc.oid) AS function_result,
    pg_get_functiondef(proc.oid) AS function_definition,
    has_function_privilege('authenticated',proc.oid,'EXECUTE') AS authenticated_execute,
    has_function_privilege('anon',proc.oid,'EXECUTE') AS anon_execute
  FROM pg_proc proc
  JOIN pg_namespace namespace ON namespace.oid=proc.pronamespace
  JOIN pg_roles owner_role ON owner_role.oid=proc.proowner
  WHERE namespace.nspname='public'
    AND proc.proname IN (
      'get_crm_client_secure','get_crm_client_secure_project_ops_base','project_operational_snapshot',
      'create_project_secure','update_project_secure','list_accessible_projects_secure','get_project_detail_secure',
      'list_project_command_center','get_project_operational_summary','get_project_health',
      'get_project_completion_readiness','change_project_status','create_project_from_won_deal',
      'can_access_project','is_project_portfolio_admin','task_dependency_blocked',
      'can_view_business_financials','can_access_task','list_project_updates_secure',
      'list_project_todos_secure','list_project_shared_attachments'
    )
), project_catalog AS (
  SELECT relation.relowner, relation.relacl, relation.relrowsecurity, relation.relforcerowsecurity,
    COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'name',policy.policyname,'permissive',policy.permissive,'roles',policy.roles,
      'command',policy.cmd,'using',policy.qual,'with_check',policy.with_check
    ) ORDER BY policy.policyname) FROM pg_policies policy
       WHERE policy.schemaname='public' AND policy.tablename='projects'),'[]'::jsonb) AS policies
  FROM pg_class relation JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
  WHERE namespace.nspname='public' AND relation.relname='projects' AND relation.relkind IN ('r','p')
), checks AS (
  SELECT 'expected_functions' AS check_name,
    NOT EXISTS(SELECT 1 FROM resolved WHERE oid IS NULL OR actual_result<>expected_result) AS passed
  UNION ALL
  SELECT 'postgres_ownership', NOT EXISTS(SELECT 1 FROM resolved WHERE oid IS NULL OR function_owner<>'postgres')
  UNION ALL
  SELECT 'security_definer_search_path', NOT EXISTS(SELECT 1 FROM resolved WHERE oid IS NULL OR NOT security_definer
    OR NOT(COALESCE(function_config,ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[]))
  UNION ALL
  SELECT 'authenticated_rpc_grants', NOT EXISTS(SELECT 1 FROM resolved WHERE access_mode='authenticated'
    AND (NOT authenticated_execute OR anon_execute))
  UNION ALL
  SELECT 'internal_rpc_revokes', NOT EXISTS(SELECT 1 FROM resolved WHERE access_mode='internal'
    AND (authenticated_execute OR anon_execute))
  UNION ALL
  SELECT 'legacy_deal_rpc_revoked', to_regprocedure('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)') IS NOT NULL
    AND NOT has_function_privilege('authenticated','public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)','EXECUTE')
  UNION ALL
  SELECT 'client_facade_transition',
    to_regprocedure('public.get_crm_client_secure(uuid)') IS NOT NULL
    AND to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') IS NOT NULL
  UNION ALL
  SELECT 'project_aggregate_and_readiness_functions',
    to_regprocedure('public.project_operational_snapshot(uuid,uuid)') IS NOT NULL
    AND to_regprocedure('public.get_project_completion_readiness(uuid)') IS NOT NULL
    AND to_regprocedure('public.get_project_health(uuid)') IS NOT NULL
    AND to_regprocedure('public.get_project_operational_summary(uuid)') IS NOT NULL
    AND to_regprocedure('public.list_project_command_center(integer,boolean,integer)') IS NOT NULL
  UNION ALL
  SELECT 'projects_rls_catalog_present', EXISTS(SELECT 1 FROM project_catalog WHERE relrowsecurity)
), catalog_state AS (
  SELECT jsonb_build_object(
    'functions',COALESCE((SELECT jsonb_agg(to_jsonb(scoped_functions) ORDER BY rendered_identity) FROM scoped_functions),'[]'::jsonb),
    'projects',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'owner',pg_get_userbyid(relowner),'acl',relacl,'rls',relrowsecurity,'force_rls',relforcerowsecurity,'policies',policies
    )) FROM project_catalog),'[]'::jsonb)
  ) AS state
), overall AS (
  SELECT bool_and(passed) AS passed FROM checks
)
SELECT 'PHASE1CATALOG|' || CASE WHEN overall.passed THEN 'PASS' ELSE 'FAIL' END || '|'
  || md5(catalog_state.state::text) AS verification_marker
FROM overall CROSS JOIN catalog_state;
