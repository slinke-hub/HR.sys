-- Read-only ACL diagnostic for the profile ordering RPC.
-- Emits only catalog/privilege metadata; never reads profile rows.
WITH target AS (
  SELECT p.oid, p.proowner, p.proacl,
         owner_role.rolname AS owner_name,
         COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner)) AS effective_acl
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = p.proowner
  WHERE n.nspname = 'public'
    AND p.oid = to_regprocedure('public.list_accessible_project_profiles()')
    AND p.prokind = 'f'
), acl_entries AS (
  SELECT t.oid, t.owner_name, t.proacl IS NULL AS uses_default_acl,
         grantee.rolname AS grantee_name,
         a.grantee = 0 AS granted_to_public,
         a.privilege_type,
         a.is_grantable,
         grantor.rolname AS grantor_name
  FROM target t
  CROSS JOIN LATERAL pg_catalog.aclexplode(t.effective_acl) AS a
  LEFT JOIN pg_catalog.pg_roles grantee ON grantee.oid = a.grantee
  LEFT JOIN pg_catalog.pg_roles grantor ON grantor.oid = a.grantor
), checks AS (
  SELECT
    EXISTS (SELECT 1 FROM target) AS signature_present,
    COALESCE((SELECT owner_name = 'postgres' FROM target), false) AS owner_is_postgres,
    COALESCE((SELECT pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE') FROM target), false) AS authenticated_effective_execute,
    COALESCE((SELECT pg_catalog.has_function_privilege('anon', oid, 'EXECUTE') FROM target), false) AS anon_effective_execute,
    COALESCE((SELECT bool_or(a.grantee = 0 AND a.privilege_type = 'EXECUTE')
              FROM target t CROSS JOIN LATERAL pg_catalog.aclexplode(t.effective_acl) a), false) AS public_direct_acl_execute,
    COALESCE((SELECT bool_or(r.rolname = 'authenticated' AND a.privilege_type = 'EXECUTE')
              FROM target t CROSS JOIN LATERAL pg_catalog.aclexplode(t.effective_acl) a
              JOIN pg_catalog.pg_roles r ON r.oid = a.grantee), false) AS authenticated_direct_acl_execute,
    COALESCE((SELECT bool_or(r.rolname = 'anon' AND a.privilege_type = 'EXECUTE')
              FROM target t CROSS JOIN LATERAL pg_catalog.aclexplode(t.effective_acl) a
              JOIN pg_catalog.pg_roles r ON r.oid = a.grantee), false) AS anon_direct_acl_execute,
    COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'grantee', COALESCE(grantee_name, CASE WHEN granted_to_public THEN 'PUBLIC' ELSE 'UNKNOWN' END),
                'privilege', privilege_type,
                'grantable', is_grantable,
                'grantor', grantor_name) ORDER BY COALESCE(grantee_name, 'PUBLIC'), privilege_type)
              FROM acl_entries), '[]'::jsonb) AS acl_entries
)
SELECT jsonb_build_object(
  'PROFILE_SIGNATURE_PRESENT', signature_present,
  'PROFILE_OWNER_IS_POSTGRES', owner_is_postgres,
  'AUTHENTICATED_EFFECTIVE_EXECUTE', authenticated_effective_execute,
  'ANON_EFFECTIVE_EXECUTE', anon_effective_execute,
  'AUTHENTICATED_DIRECT_ACL_EXECUTE', authenticated_direct_acl_execute,
  'ANON_DIRECT_ACL_EXECUTE', anon_direct_acl_execute,
  'PUBLIC_DIRECT_ACL_EXECUTE', public_direct_acl_execute,
  'DIRECT_ACL_ENTRIES', acl_entries,
  'EXPECTED_ACL', 'authenticated=EXECUTE; anon=NONE; PUBLIC=NONE'
) AS project_profile_order_acl_check
FROM checks;
