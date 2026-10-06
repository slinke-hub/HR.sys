-- Staging-only, read-only catalog diagnostic for the 20260930101000 Client
-- service migration as subsequently wrapped by Project Operations Phase 1.
-- No CRM/client/business rows are selected. Function bodies are inspected only
-- to return boolean markers; definitions and secrets are never emitted.
WITH expected(signature, function_name, expected_result, expected_language, access_mode, version_role) AS (
  VALUES
    ('public.crm_client_dto(public.crm_clients)', 'crm_client_dto', 'jsonb', 'sql', 'internal', 'original'),
    ('public.list_crm_clients_secure(text)', 'list_crm_clients_secure', 'SETOF jsonb', 'sql', 'authenticated', 'original'),
    ('public.get_crm_client_secure(uuid)', 'get_crm_client_secure', 'jsonb', 'plpgsql', 'authenticated', 'phase1_facade'),
    ('public.create_crm_client_secure(jsonb)', 'create_crm_client_secure', 'jsonb', 'plpgsql', 'authenticated', 'original'),
    ('public.update_crm_client_secure(uuid,jsonb)', 'update_crm_client_secure', 'jsonb', 'plpgsql', 'authenticated', 'original'),
    ('public.delete_crm_client_secure(uuid)', 'delete_crm_client_secure', 'boolean', 'plpgsql', 'authenticated', 'original'),
    ('public.get_crm_client_secure_project_ops_base(uuid)', 'get_crm_client_secure_project_ops_base', 'jsonb', 'plpgsql', 'internal', 'phase1_base')
), resolved AS (
  SELECT e.*,
    to_regprocedure(e.signature) AS expected_oid,
    p.oid,
    pg_get_function_result(p.oid) AS actual_result,
    owner_role.rolname AS function_owner,
    p.prosecdef,
    p.proconfig,
    language.lanname,
    COALESCE(has_function_privilege('authenticated', p.oid, 'EXECUTE'), false) AS auth_execute,
    COALESCE(has_function_privilege('anon', p.oid, 'EXECUTE'), false) AS anon_execute,
    COALESCE((SELECT bool_or(a.grantee = 0 AND a.privilege_type = 'EXECUTE')
              FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a), false) AS public_execute,
    COALESCE(pg_get_functiondef(p.oid), '') AS definition
  FROM expected e
  LEFT JOIN pg_proc p ON p.oid = to_regprocedure(e.signature)
  LEFT JOIN pg_roles owner_role ON owner_role.oid = p.proowner
  LEFT JOIN pg_language language ON language.oid = p.prolang
), properties AS (
  SELECT signature, function_name, version_role, property, passed, detail
  FROM resolved r
  CROSS JOIN LATERAL (VALUES
    ('EXACT_SIGNATURE', expected_oid IS NOT NULL AND oid = expected_oid,
      'expected_oid=' || COALESCE(expected_oid::text, 'NULL') || '; actual_oid=' || COALESCE(oid::text, 'MISSING')),
    ('RETURN_TYPE', oid IS NOT NULL AND actual_result = expected_result,
      'expected=' || expected_result || '; actual=' || COALESCE(actual_result, 'MISSING')),
    ('LANGUAGE', oid IS NOT NULL AND lanname = expected_language,
      'expected=' || expected_language || '; actual=' || COALESCE(lanname, 'MISSING')),
    ('OWNER', oid IS NOT NULL AND function_owner = 'postgres',
      'expected=postgres; actual=' || COALESCE(function_owner, 'MISSING')),
    ('SECURITY_DEFINER', oid IS NOT NULL AND prosecdef,
      'expected=DEFINER; actual=' || CASE WHEN oid IS NULL THEN 'MISSING' WHEN prosecdef THEN 'DEFINER' ELSE 'INVOKER' END),
    ('SEARCH_PATH', oid IS NOT NULL AND COALESCE(proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[],
      'expected=search_path=public, pg_temp; actual=' || COALESCE(proconfig::text, 'MISSING')),
    ('EXECUTE_ACL', oid IS NOT NULL AND CASE WHEN access_mode = 'authenticated'
        THEN auth_execute AND NOT anon_execute AND NOT public_execute
        ELSE NOT auth_execute AND NOT anon_execute AND NOT public_execute END,
      'mode=' || access_mode || '; authenticated=' || auth_execute::text || '; anon=' || anon_execute::text || '; public=' || public_execute::text),
    ('BODY_MARKERS', oid IS NOT NULL AND CASE function_name
        WHEN 'crm_client_dto' THEN definition ILIKE '%assigned_employee%' AND definition ILIKE '%jsonb_build_object%'
        WHEN 'list_crm_clients_secure' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%crm_client_dto%'
        WHEN 'get_crm_client_secure' THEN definition ILIKE '%get_crm_client_secure_project_ops_base%' AND definition ILIKE '%project_operational_snapshot%' AND definition ILIKE '%can_access_project%'
        WHEN 'create_crm_client_secure' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%INSERT INTO public.crm_clients%'
        WHEN 'update_crm_client_secure' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%UPDATE public.crm_clients%'
        WHEN 'delete_crm_client_secure' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%DELETE FROM public.crm_clients%'
        WHEN 'get_crm_client_secure_project_ops_base' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%crm_client_dto%'
        ELSE false END,
      CASE WHEN function_name = 'get_crm_client_secure' THEN 'Phase1 wrapper delegates CRM authorization and adds project_operational_snapshot'
           WHEN function_name = 'get_crm_client_secure_project_ops_base' THEN 'renamed original CRM-authorized detail implementation'
           ELSE 'original secure Client RPC behavior markers' END)
  ) v(property, passed, detail)
), same_name AS (
  SELECT e.function_name,
    COALESCE(jsonb_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
      ORDER BY pg_get_function_identity_arguments(p.oid)) FILTER (WHERE p.oid IS NOT NULL), '[]'::jsonb) AS overloads,
    count(p.oid) FILTER (WHERE p.oid IS NOT NULL) AS overload_count,
    bool_and(p.oid = to_regprocedure(e.signature)) FILTER (WHERE p.oid IS NOT NULL) AS only_expected
  FROM (SELECT DISTINCT function_name, signature FROM expected) e
  LEFT JOIN pg_proc p ON p.proname = e.function_name
  LEFT JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE p.oid IS NULL OR n.oid IS NOT NULL
  GROUP BY e.function_name
), facade AS (
  SELECT
    to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') IS NOT NULL AS base_present,
    to_regprocedure('public.get_crm_client_secure(uuid)') IS NOT NULL AS facade_present,
    EXISTS (SELECT 1 FROM resolved WHERE function_name='get_crm_client_secure_project_ops_base'
      AND oid IS NOT NULL AND prosecdef AND NOT auth_execute AND NOT anon_execute AND NOT public_execute
      AND COALESCE(proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[]
      AND definition ILIKE '%can_access_crm%') AS base_valid,
    EXISTS (SELECT 1 FROM resolved WHERE function_name='get_crm_client_secure'
      AND oid IS NOT NULL AND prosecdef AND auth_execute AND NOT anon_execute AND NOT public_execute
      AND COALESCE(proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[]
      AND definition ILIKE '%get_crm_client_secure_project_ops_base%'
      AND definition ILIKE '%project_operational_snapshot%'
      AND definition ILIKE '%can_access_project%') AS facade_valid
), client_table AS (
  SELECT c.relrowsecurity AS rls_enabled,
    has_table_privilege('authenticated', 'public.crm_clients', 'SELECT') AS auth_select,
    has_table_privilege('authenticated', 'public.crm_clients', 'INSERT') AS auth_insert,
    has_table_privilege('authenticated', 'public.crm_clients', 'UPDATE') AS auth_update,
    has_table_privilege('authenticated', 'public.crm_clients', 'DELETE') AS auth_delete,
    has_any_column_privilege('authenticated', 'public.crm_clients', 'INSERT') AS auth_column_insert,
    has_any_column_privilege('authenticated', 'public.crm_clients', 'UPDATE') AS auth_column_update,
    has_table_privilege('anon', 'public.crm_clients', 'SELECT') AS anon_select,
    has_table_privilege('anon', 'public.crm_clients', 'INSERT') AS anon_insert,
    has_table_privilege('anon', 'public.crm_clients', 'UPDATE') AS anon_update,
    has_table_privilege('anon', 'public.crm_clients', 'DELETE') AS anon_delete,
    has_any_column_privilege('anon', 'public.crm_clients', 'INSERT') AS anon_column_insert,
    has_any_column_privilege('anon', 'public.crm_clients', 'UPDATE') AS anon_column_update,
    NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='crm_clients'
      AND policyname IN ('Users can view clients','Users can insert clients','Users can update clients','Users can delete clients')) AS legacy_policies_absent
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='crm_clients' AND c.relkind IN ('r','p')
), version_state AS (
  SELECT
    NOT EXISTS (SELECT 1 FROM resolved WHERE oid IS NULL OR actual_result IS DISTINCT FROM expected_result OR lanname IS DISTINCT FROM expected_language
      OR function_owner IS DISTINCT FROM 'postgres' OR NOT prosecdef
      OR NOT (COALESCE(proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[])
      OR NOT CASE WHEN access_mode='authenticated' THEN auth_execute AND NOT anon_execute AND NOT public_execute
                  ELSE NOT auth_execute AND NOT anon_execute AND NOT public_execute END
      OR NOT CASE function_name
        WHEN 'crm_client_dto' THEN definition ILIKE '%assigned_employee%' AND definition ILIKE '%jsonb_build_object%'
        WHEN 'list_crm_clients_secure' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%crm_client_dto%'
        WHEN 'get_crm_client_secure' THEN definition ILIKE '%get_crm_client_secure_project_ops_base%' AND definition ILIKE '%project_operational_snapshot%' AND definition ILIKE '%can_access_project%'
        WHEN 'create_crm_client_secure' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%INSERT INTO public.crm_clients%'
        WHEN 'update_crm_client_secure' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%UPDATE public.crm_clients%'
        WHEN 'delete_crm_client_secure' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%DELETE FROM public.crm_clients%'
        WHEN 'get_crm_client_secure_project_ops_base' THEN definition ILIKE '%can_access_crm%' AND definition ILIKE '%crm_client_dto%'
        ELSE false END) AS all_rpc_effects_present,
    NOT EXISTS (SELECT 1 FROM same_name WHERE overload_count > 1 OR only_expected IS DISTINCT FROM true) AS no_conflicting_overloads,
    EXISTS (SELECT 1 FROM client_table WHERE rls_enabled AND auth_select AND NOT auth_insert AND NOT auth_update AND NOT auth_delete
      AND NOT auth_column_insert AND NOT auth_column_update
      AND NOT anon_select AND NOT anon_insert AND NOT anon_update AND NOT anon_delete
      AND NOT anon_column_insert AND NOT anon_column_update AND legacy_policies_absent) AS table_security_valid,
    EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260930101000') AS history_recorded
), final_state AS (
  SELECT f.*,
    s.all_rpc_effects_present AND s.no_conflicting_overloads AS durable_effects_complete,
    s.table_security_valid AS security_boundary_valid,
    s.all_rpc_effects_present AND s.no_conflicting_overloads AND s.table_security_valid AS client_durable_effects_complete,
    s.all_rpc_effects_present AND s.no_conflicting_overloads AND s.table_security_valid AND NOT s.history_recorded AS safe_to_reconcile_history,
    s.history_recorded
  FROM facade f CROSS JOIN version_state s
)
SELECT jsonb_build_object(
  'checks', (SELECT jsonb_agg(jsonb_build_object('function', function_name, 'signature', signature,
       'version_role', version_role, 'property', property, 'pass', passed, 'detail', detail)
       ORDER BY function_name, property) FROM properties),
  'overloads', (SELECT jsonb_object_agg(function_name, jsonb_build_object('count', overload_count, 'identities', overloads, 'only_expected', COALESCE(only_expected,false))) FROM same_name),
  'summary', jsonb_build_object(
    'CLIENT_DURABLE_EFFECTS_COMPLETE', final_state.client_durable_effects_complete,
    'PHASE1_CLIENT_BASE_PRESENT', final_state.base_present,
    'PHASE1_CLIENT_FACADE_PRESENT', final_state.facade_present,
    'CLIENT_TABLE_PRESENT', EXISTS (SELECT 1 FROM client_table),
    'CLIENT_SECURITY_BOUNDARY_VALID', final_state.security_boundary_valid,
    'GENUINELY_MISSING_OBJECTS', COALESCE((SELECT jsonb_agg(signature ORDER BY signature) FROM resolved WHERE oid IS NULL), '[]'::jsonb),
    'WRONG_SIGNATURES', COALESCE((SELECT jsonb_agg(function_name || ':' || signature ORDER BY function_name) FROM resolved WHERE expected_oid IS NULL OR oid IS NULL), '[]'::jsonb),
    'WRONG_PROPERTIES', COALESCE((SELECT jsonb_agg(function_name || ':' || property ORDER BY function_name, property) FROM properties WHERE NOT passed), '[]'::jsonb),
    'STALE_DIAGNOSTIC_ASSERTIONS', CASE
      WHEN final_state.client_durable_effects_complete AND NOT final_state.history_recorded THEN jsonb_build_array('20260930101000 aggregate check failure is stale relative to validated Phase 1 replacement and complete Client durable state')
      ELSE '[]'::jsonb END,
    'SAFE_TO_RECONCILE_20260930101000_HISTORY', final_state.safe_to_reconcile_history,
    'HISTORY_ALREADY_RECORDED', final_state.history_recorded,
    'ORIGINAL_GET_RPC_STATUS', 'INTENTIONALLY_SUPERSEDED_BY_PHASE1_FACADE',
    'PHASE1_BASE_VALID', final_state.base_present AND (SELECT base_valid FROM facade),
    'PHASE1_FACADE_VALID', final_state.facade_present AND (SELECT facade_valid FROM facade)
  )
) AS client_reconciliation
FROM final_state;
