BEGIN;

-- CRM users need a deliberately narrow company directory to assign Won projects.
-- This avoids granting broad SELECT access to private profile fields.
CREATE OR REPLACE FUNCTION public.list_active_project_assignment_employees()
RETURNS TABLE (
    id UUID,
    emp_index INTEGER,
    full_name TEXT,
    display_name_ar TEXT,
    role TEXT,
    avatar_url TEXT,
    job_title TEXT,
    job_title_ar TEXT,
    department_id UUID,
    manager_id UUID,
    is_active BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'CRM access is required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        profile.id,
        profile.emp_index,
        profile.full_name::TEXT,
        profile.display_name_ar::TEXT,
        profile.role::TEXT,
        profile.avatar_url::TEXT,
        profile.job_title::TEXT,
        profile.job_title_ar::TEXT,
        profile.department_id,
        profile.manager_id,
        profile.is_active
    FROM public.profiles profile
    WHERE profile.is_active IS DISTINCT FROM FALSE
    ORDER BY profile.emp_index NULLS LAST, profile.full_name;
END;
$$;

-- Project viewers only receive the names needed to understand their accessible
-- project team and To-Do assignments. Portfolio administrators receive the
-- complete active directory used by the project editor.
CREATE OR REPLACE FUNCTION public.list_accessible_project_profiles()
RETURNS TABLE (
    id UUID,
    emp_index INTEGER,
    full_name TEXT,
    display_name_ar TEXT,
    role TEXT,
    avatar_url TEXT,
    job_title TEXT,
    job_title_ar TEXT,
    department_id UUID,
    manager_id UUID,
    is_active BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication is required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT DISTINCT
        profile.id,
        profile.emp_index,
        profile.full_name::TEXT,
        profile.display_name_ar::TEXT,
        profile.role::TEXT,
        profile.avatar_url::TEXT,
        profile.job_title::TEXT,
        profile.job_title_ar::TEXT,
        profile.department_id,
        profile.manager_id,
        profile.is_active
    FROM public.profiles profile
    WHERE profile.is_active IS DISTINCT FROM FALSE
      AND (
          public.is_project_portfolio_admin(auth.uid())
          OR EXISTS (
              SELECT 1
              FROM public.projects project
              WHERE public.can_access_project(project.id, auth.uid())
                AND (
                    profile.id = project.created_by
                    OR profile.id = project.project_manager_id
                    OR profile.id = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
                )
          )
      )
    ORDER BY profile.emp_index NULLS LAST, profile.full_name;
END;
$$;

-- A project assignee may read the full project command center and its related
-- updates and To-Do items, but the existing update/delete policies still keep
-- project administration limited to managers, owners, and administrators.
CREATE OR REPLACE FUNCTION public.can_access_project(
    p_project_id UUID,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.projects project
        WHERE project.id = p_project_id
          AND (
              project.created_by = p_user_id
              OR project.project_manager_id = p_user_id
              OR p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
              OR public.is_project_portfolio_admin(p_user_id)
          )
    );
$$;

DROP POLICY IF EXISTS project_portfolio_select ON public.projects;
CREATE POLICY project_portfolio_select
ON public.projects
FOR SELECT TO authenticated
USING (
    created_by = auth.uid()
    OR project_manager_id = auth.uid()
    OR auth.uid() = ANY(COALESCE(assigned_people, ARRAY[]::UUID[]))
    OR public.is_project_portfolio_admin(auth.uid())
);

REVOKE ALL ON FUNCTION public.list_active_project_assignment_employees() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_accessible_project_profiles() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_access_project(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_active_project_assignment_employees() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_accessible_project_profiles() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_project(UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
