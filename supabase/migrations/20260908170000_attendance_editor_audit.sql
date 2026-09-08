-- Record the administrator who last corrected each individual attendance punch.
BEGIN;

ALTER TABLE public.attendance
    ADD COLUMN IF NOT EXISTS clock_in_edited_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS clock_in_edited_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS clock_out_edited_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS clock_out_edited_at TIMESTAMPTZ;

COMMENT ON COLUMN public.attendance.clock_in_edited_by IS 'Administrator or executive who last corrected the clock-in punch.';
COMMENT ON COLUMN public.attendance.clock_out_edited_by IS 'Administrator or executive who last corrected the clock-out punch.';

CREATE OR REPLACE FUNCTION public.record_attendance_editor()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    viewer_can_manage BOOLEAN := public.can_manage_attendance_records(auth.uid());
BEGIN
    IF viewer_can_manage THEN
        IF NEW.date IS DISTINCT FROM OLD.date
           OR NEW.clock_in_time IS DISTINCT FROM OLD.clock_in_time
           OR NEW.clock_in_location IS DISTINCT FROM OLD.clock_in_location THEN
            NEW.clock_in_edited_by := auth.uid();
            NEW.clock_in_edited_at := NOW();
        END IF;

        IF NEW.clock_out_time IS DISTINCT FROM OLD.clock_out_time
           OR NEW.clock_out_location IS DISTINCT FROM OLD.clock_out_location
           OR NEW.clock_out_type IS DISTINCT FROM OLD.clock_out_type
           OR NEW.overtime_hours IS DISTINCT FROM OLD.overtime_hours THEN
            NEW.clock_out_edited_by := auth.uid();
            NEW.clock_out_edited_at := NOW();
        END IF;
    ELSE
        -- Audit fields are database-managed and cannot be forged by employees.
        NEW.clock_in_edited_by := OLD.clock_in_edited_by;
        NEW.clock_in_edited_at := OLD.clock_in_edited_at;
        NEW.clock_out_edited_by := OLD.clock_out_edited_by;
        NEW.clock_out_edited_at := OLD.clock_out_edited_at;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS attendance_editor_audit ON public.attendance;
CREATE TRIGGER attendance_editor_audit
BEFORE UPDATE ON public.attendance
FOR EACH ROW
EXECUTE FUNCTION public.record_attendance_editor();

NOTIFY pgrst, 'reload schema';

COMMIT;
