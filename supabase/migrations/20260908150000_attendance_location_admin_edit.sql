-- Require verified coordinates for attendance punches and let administrators
-- correct attendance records for any employee.
BEGIN;

CREATE OR REPLACE FUNCTION public.is_valid_attendance_coordinates(candidate TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    latitude NUMERIC;
    longitude NUMERIC;
BEGIN
    IF BTRIM(COALESCE(candidate, '')) !~ '^-?[0-9]+(?:\.[0-9]+)?\s*,\s*-?[0-9]+(?:\.[0-9]+)?$' THEN
        RETURN FALSE;
    END IF;
    latitude := BTRIM(SPLIT_PART(candidate, ',', 1))::NUMERIC;
    longitude := BTRIM(SPLIT_PART(candidate, ',', 2))::NUMERIC;
    RETURN latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180;
EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_manage_attendance_records(p_user_id UUID DEFAULT auth.uid())
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
              OR UPPER(BTRIM(COALESCE(viewer.job_title, ''))) IN (
                  'GM', 'GENERAL MANAGER', 'GENERAL MANAGER (GM)',
                  'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER', 'CHIEF EXECUTIVE OFFICER (CEO)'
              )
              OR BTRIM(COALESCE(viewer.job_title_ar, '')) IN ('المدير العام', 'الرئيس التنفيذي')
          )
    );
$$;

REVOKE ALL ON FUNCTION public.is_valid_attendance_coordinates(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_manage_attendance_records(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_valid_attendance_coordinates(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_attendance_records(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_valid_attendance_coordinates(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_attendance_records(UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.enforce_attendance_coordinates()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF (TG_OP = 'INSERT' OR NEW.clock_in_time IS DISTINCT FROM OLD.clock_in_time OR NEW.clock_in_location IS DISTINCT FROM OLD.clock_in_location)
       AND NEW.clock_in_time IS NOT NULL
       AND NOT public.is_valid_attendance_coordinates(NEW.clock_in_location) THEN
        RAISE EXCEPTION 'Clock-in requires valid latitude and longitude coordinates' USING ERRCODE = '23514';
    END IF;
    IF (TG_OP = 'INSERT' OR NEW.clock_out_time IS DISTINCT FROM OLD.clock_out_time OR NEW.clock_out_location IS DISTINCT FROM OLD.clock_out_location)
       AND NEW.clock_out_time IS NOT NULL
       AND NOT public.is_valid_attendance_coordinates(NEW.clock_out_location) THEN
        RAISE EXCEPTION 'Clock-out requires valid latitude and longitude coordinates' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS attendance_coordinates_required ON public.attendance;
CREATE TRIGGER attendance_coordinates_required
BEFORE INSERT OR UPDATE OF clock_in_time, clock_in_location, clock_out_time, clock_out_location
ON public.attendance
FOR EACH ROW
EXECUTE FUNCTION public.enforce_attendance_coordinates();

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_company_attendance_select ON public.attendance;
CREATE POLICY admin_company_attendance_select
ON public.attendance
FOR SELECT
TO authenticated
USING (public.can_manage_attendance_records(auth.uid()));

DROP POLICY IF EXISTS admin_company_attendance_update ON public.attendance;
CREATE POLICY admin_company_attendance_update
ON public.attendance
FOR UPDATE
TO authenticated
USING (public.can_manage_attendance_records(auth.uid()))
WITH CHECK (public.can_manage_attendance_records(auth.uid()));

NOTIFY pgrst, 'reload schema';

COMMIT;
