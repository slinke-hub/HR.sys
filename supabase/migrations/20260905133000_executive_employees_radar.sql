-- Give authorized leaders a privacy-limited, live view of today's employee
-- attendance states for the Employees Radar dashboard widget.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_view_employees_radar(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
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
              UPPER(REGEXP_REPLACE(BTRIM(COALESCE(viewer.role, '')), '[_-]+', ' ', 'g')) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'MANAGER', 'SUPERVISOR', 'GENERAL MANAGER', 'GM', 'CEO'
              )
              OR UPPER(REGEXP_REPLACE(BTRIM(COALESCE(viewer.job_title, '')), '[_-]+', ' ', 'g')) IN (
                  'IT MANAGER', 'GENERAL MANAGER', 'GM', 'CEO', 'CHIEF EXECUTIVE OFFICER'
              )
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_view_employees_radar(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_employees_radar(UUID) TO authenticated;

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'attendance'
          AND policyname = 'employees_radar_company_attendance_select'
    ) THEN
        EXECUTE 'CREATE POLICY employees_radar_company_attendance_select ON public.attendance FOR SELECT TO authenticated USING (public.can_view_employees_radar(auth.uid()) AND date = (NOW() AT TIME ZONE ''Asia/Riyadh'')::DATE)';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_employees_radar(p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    attendance_id UUID,
    employee_id UUID,
    full_name TEXT,
    clock_in_time TIMESTAMPTZ,
    clock_out_time TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    WITH latest_attendance AS (
        SELECT DISTINCT ON (record.employee_id)
            record.id AS attendance_id,
            record.employee_id,
            COALESCE(profile.full_name, 'Employee') AS full_name,
            record.clock_in_time,
            record.clock_out_time
        FROM public.attendance record
        JOIN public.profiles profile ON profile.id = record.employee_id
        WHERE public.can_view_employees_radar(auth.uid())
          AND record.date = p_date
          AND record.clock_in_time IS NOT NULL
          AND profile.is_active IS DISTINCT FROM FALSE
        ORDER BY record.employee_id, record.clock_in_time DESC NULLS LAST, record.created_at DESC
    )
    SELECT *
    FROM latest_attendance
    ORDER BY (clock_out_time IS NULL) DESC, COALESCE(clock_out_time, clock_in_time) DESC;
$$;

REVOKE ALL ON FUNCTION public.get_employees_radar(DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_employees_radar(DATE) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
