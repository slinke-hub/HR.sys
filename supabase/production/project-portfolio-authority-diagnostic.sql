-- Read-only production diagnostic. This returns metadata and counts only.
-- Run with an administrative read-only database context; it does not simulate
-- a browser user and performs no schema, data, or privilege changes.

SELECT
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    p.prosecdef AS security_definer,
    owner_role.rolname AS function_owner,
    p.proconfig AS function_configuration,
    pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles owner_role ON owner_role.oid = p.proowner
WHERE n.nspname = 'public'
  AND p.proname IN (
      'list_accessible_projects_secure',
      'can_access_project',
      'is_project_portfolio_admin'
  )
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

SELECT
    routine_schema,
    routine_name,
    specific_name,
    grantee,
    privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
      'list_accessible_projects_secure',
      'can_access_project',
      'is_project_portfolio_admin'
  )
ORDER BY routine_name, grantee, privilege_type;

SELECT
    c.oid::regclass AS table_name,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'projects';

SELECT
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'projects'
ORDER BY policyname;

WITH active_admin_profiles AS (
    SELECT
        profile.id,
        profile.role,
        profile.job_title,
        profile.is_active,
        public.is_project_portfolio_admin(profile.id) AS is_project_portfolio_admin
    FROM public.profiles profile
    WHERE profile.is_active IS DISTINCT FROM FALSE
      AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
          'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
          'MANAGER', 'SUPERVISOR', 'GM', 'GENERAL MANAGER',
          'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
      )
)
SELECT
    role,
    job_title,
    is_active,
    is_project_portfolio_admin,
    (SELECT COUNT(*) FROM public.projects) AS total_project_rows,
    (
        SELECT COUNT(*)
        FROM public.projects project
        WHERE public.can_access_project(project.id, active_admin_profiles.id)
    ) AS accessible_project_rows,
    (
        SELECT COUNT(*)
        FROM public.projects project
        WHERE project.created_by = active_admin_profiles.id
           OR project.project_manager_id = active_admin_profiles.id
           OR active_admin_profiles.id = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
    ) AS direct_relationship_rows
FROM active_admin_profiles
ORDER BY role, job_title;
