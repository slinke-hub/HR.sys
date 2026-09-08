-- Guarantee company-wide employee name visibility for CEO and GM accounts.
-- The application still keeps User Management hidden from executive accounts.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_view_company_employee_names(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'
              )
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.job_title, ''), '[_-]+', ' ', 'g'))) IN (
                  'GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
              )
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_view_company_employee_names(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_company_employee_names(UUID) TO authenticated;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS executive_company_employee_names_select ON public.profiles;
CREATE POLICY executive_company_employee_names_select
ON public.profiles
FOR SELECT
TO authenticated
USING (public.can_view_company_employee_names(auth.uid()));

NOTIFY pgrst, 'reload schema';

COMMIT;
