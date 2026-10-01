BEGIN;

-- Fix PostgreSQL's SELECT DISTINCT ordering rule without changing the
-- project-profile authorization contract or returned columns.
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
    ORDER BY profile.emp_index NULLS LAST, profile.full_name::TEXT;
END;
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
