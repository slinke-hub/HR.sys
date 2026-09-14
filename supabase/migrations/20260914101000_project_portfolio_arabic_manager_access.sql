-- Keep Arabic Manager and Supervisor job titles aligned with the restricted
-- project command-center access rules introduced for project To-Do assignees.
BEGIN;

CREATE OR REPLACE FUNCTION public.is_project_portfolio_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'MANAGER', 'SUPERVISOR', 'GM', 'GENERAL MANAGER',
                  'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
              )
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) ~
                 '(^| )(MANAGER|SUPERVISOR|GM|GENERAL MANAGER|CEO|CHIEF EXECUTIVE|CHIEF EXECUTIVE OFFICER)( |$)'
              OR BTRIM(COALESCE(profile.job_title_ar, '')) ~ '(مدير|مشرف)'
          )
    );
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
