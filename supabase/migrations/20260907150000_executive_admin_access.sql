-- Give GM and CEO profiles administrator-level application and RLS access.
-- User Management remains hidden and blocked by the application UI.
BEGIN;

CREATE OR REPLACE FUNCTION public.is_executive_admin_title(candidate_title TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT UPPER(BTRIM(REGEXP_REPLACE(COALESCE(candidate_title, ''), '[_-]+', ' ', 'g')))
        IN ('GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER');
$$;

CREATE OR REPLACE FUNCTION public.enforce_executive_admin_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF public.is_executive_admin_title(NEW.job_title) THEN
        NEW.role := 'ADMIN';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_executive_admin_role ON public.profiles;
CREATE TRIGGER profiles_executive_admin_role
BEFORE INSERT OR UPDATE OF job_title, role ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.enforce_executive_admin_role();

UPDATE public.profiles
SET role = 'ADMIN'
WHERE public.is_executive_admin_title(job_title)
  AND UPPER(COALESCE(role, '')) <> 'ADMIN';

CREATE OR REPLACE FUNCTION public.can_view_all_attendance(p_user_id UUID DEFAULT auth.uid())
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
              OR public.is_executive_admin_title(viewer.job_title)
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_view_all_attendance(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_all_attendance(UUID) TO authenticated;

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS executive_admin_full_attendance_select ON public.attendance;
CREATE POLICY executive_admin_full_attendance_select
ON public.attendance
FOR SELECT
TO authenticated
USING (public.can_view_all_attendance(auth.uid()));

NOTIFY pgrst, 'reload schema';

COMMIT;
