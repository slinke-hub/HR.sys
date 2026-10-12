-- Read-only preflight/post-application verification for the profile ordering fix.
-- Run only against staging; output contains catalog booleans, no profile rows.
WITH expected AS (
  SELECT to_regprocedure('public.list_accessible_project_profiles()') AS expected_oid
), target AS (
  SELECT p.oid, p.proowner, p.proacl, p.prosecdef, p.proconfig,
         pg_catalog.pg_get_function_result(p.oid) AS result_contract,
         pg_catalog.pg_get_functiondef(p.oid) AS definition,
         owner_role.rolname AS owner_name
  FROM expected e
  JOIN pg_catalog.pg_proc p ON p.oid = e.expected_oid
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = p.proowner
  WHERE p.prokind = 'f'
), checks AS (
  SELECT
    e.expected_oid IS NOT NULL AS signature_present,
    (SELECT count(*) = 1
     FROM pg_catalog.pg_proc p
     JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'list_accessible_project_profiles'
       AND p.prokind = 'f') AS overload_set_ok,
    t.result_contract = 'TABLE(id uuid, emp_index integer, full_name text, display_name_ar text, role text, avatar_url text, job_title text, job_title_ar text, department_id uuid, manager_id uuid, is_active boolean)' AS return_contract_ok,
    t.owner_name = 'postgres' AS owner_ok,
    t.prosecdef AS security_definer_ok,
    COALESCE(t.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']::text[] AS search_path_ok,
    COALESCE(pg_catalog.has_function_privilege('authenticated', t.oid, 'EXECUTE'), false)
      AND NOT COALESCE(pg_catalog.has_function_privilege('anon', t.oid, 'EXECUTE'), false)
      AND NOT COALESCE((
        SELECT bool_or(a.grantee = 0 AND a.privilege_type = 'EXECUTE')
        FROM pg_catalog.aclexplode(COALESCE(t.proacl, pg_catalog.acldefault('f', t.proowner))) AS a
      ), false) AS grants_ok,
    COALESCE(pg_catalog.has_function_privilege('authenticated', t.oid, 'EXECUTE'), false) AS authenticated_effective_execute,
    COALESCE(pg_catalog.has_function_privilege('anon', t.oid, 'EXECUTE'), false) AS anon_effective_execute,
    COALESCE((
      SELECT bool_or(a.grantee = 0 AND a.privilege_type = 'EXECUTE')
      FROM pg_catalog.aclexplode(COALESCE(t.proacl, pg_catalog.acldefault('f', t.proowner))) AS a
    ), false) AS public_direct_execute,
    COALESCE((
      SELECT bool_or(a.grantee = r.oid AND a.privilege_type = 'EXECUTE')
      FROM pg_catalog.aclexplode(COALESCE(t.proacl, pg_catalog.acldefault('f', t.proowner))) AS a
      CROSS JOIN pg_catalog.pg_roles r
      WHERE r.rolname = 'authenticated'
    ), false) AS authenticated_direct_execute,
    COALESCE((
      SELECT bool_or(a.grantee = r.oid AND a.privilege_type = 'EXECUTE')
      FROM pg_catalog.aclexplode(COALESCE(t.proacl, pg_catalog.acldefault('f', t.proowner))) AS a
      CROSS JOIN pg_catalog.pg_roles r
      WHERE r.rolname = 'anon'
    ), false) AS anon_direct_execute,
    COALESCE(t.definition, '') ILIKE '%SELECT DISTINCT%' AS distinct_present,
    regexp_replace(lower(COALESCE(t.definition, '')), '\s+', ' ', 'g')
      LIKE '%order by profile.emp_index nulls last, profile.full_name::text%' AS ordering_fix_present,
    EXISTS (
      SELECT 1 FROM supabase_migrations.schema_migrations sm
      WHERE sm.version = '20261001090000'
    ) AS migration_history_present
  FROM expected e
  LEFT JOIN target t ON true
), final AS (
  SELECT *,
    signature_present AND overload_set_ok AND return_contract_ok AND owner_ok AND security_definer_ok
      AND search_path_ok AND distinct_present AND NOT ordering_fix_present AND NOT migration_history_present
      AS ordering_migration_required,
    signature_present AND overload_set_ok AND return_contract_ok AND owner_ok AND security_definer_ok
      AND search_path_ok AND authenticated_effective_execute AND authenticated_direct_execute
      AND NOT anon_effective_execute AND NOT anon_direct_execute AND NOT public_direct_execute
      AND ordering_fix_present AS final_profile_directory_state_valid,
    authenticated_effective_execute AND authenticated_direct_execute
      AND NOT anon_effective_execute AND NOT anon_direct_execute AND NOT public_direct_execute AS acl_valid
  FROM checks
)
SELECT jsonb_build_object(
  'PROFILE_SIGNATURE_PRESENT', signature_present,
  'PROFILE_OVERLOAD_SET_OK', overload_set_ok,
  'PROFILE_RETURN_CONTRACT_OK', return_contract_ok,
  'PROFILE_OWNER_OK', owner_ok,
  'PROFILE_SECURITY_DEFINER_OK', security_definer_ok,
  'PROFILE_SEARCH_PATH_OK', search_path_ok,
  'PROFILE_GRANTS_OK', grants_ok,
  'AUTHENTICATED_EFFECTIVE_EXECUTE', authenticated_effective_execute,
  'AUTHENTICATED_DIRECT_EXECUTE', authenticated_direct_execute,
  'ANON_EFFECTIVE_EXECUTE', anon_effective_execute,
  'ANON_DIRECT_EXECUTE', anon_direct_execute,
  'PUBLIC_DIRECT_EXECUTE', public_direct_execute,
  'PROFILE_DISTINCT_PRESENT', distinct_present,
  'PROFILE_ORDERING_FIX_PRESENT', ordering_fix_present,
  'MIGRATION_HISTORY_PRESENT', migration_history_present,
  'ORDERING_MIGRATION_REQUIRED', ordering_migration_required,
  'ACL_CORRECTION_REQUIRED', NOT acl_valid,
  'ORDERING_VALID', ordering_fix_present,
  'ACL_VALID', acl_valid,
  'FINAL_PROFILE_DIRECTORY_STATE_VALID', final_profile_directory_state_valid
) AS project_profile_order_check
FROM final;
