-- Add structured short-leave data to the existing leave workflow.
BEGIN;

ALTER TABLE public.leave_requests
    ADD COLUMN IF NOT EXISTS short_leave_reason TEXT,
    ADD COLUMN IF NOT EXISTS short_leave_duration_minutes INTEGER;

CREATE OR REPLACE FUNCTION public.validate_short_leave_request()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    IF NEW.leave_type='Short Leave' THEN
        IF NEW.short_leave_reason NOT IN (
            'I am running late to the office.',
            'I will be out for a meeting.',
            'I need to attend an urgent family matter.'
        ) THEN RAISE EXCEPTION 'Select a valid short leave reason'; END IF;
        IF NEW.short_leave_duration_minutes NOT IN (15,60,120,180) THEN
            RAISE EXCEPTION 'Short leave duration must be 15, 60, 120 or 180 minutes';
        END IF;
        NEW.start_date:=COALESCE(NEW.start_date,CURRENT_DATE);
        NEW.end_date:=NEW.start_date;
        NEW.reason:=NEW.short_leave_reason;
    ELSE
        NEW.short_leave_reason:=NULL;
        NEW.short_leave_duration_minutes:=NULL;
    END IF;
    RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS validate_short_leave_request_trigger ON public.leave_requests;
CREATE TRIGGER validate_short_leave_request_trigger
BEFORE INSERT OR UPDATE OF leave_type,short_leave_reason,short_leave_duration_minutes ON public.leave_requests
FOR EACH ROW EXECUTE FUNCTION public.validate_short_leave_request();

NOTIFY pgrst,'reload schema';
COMMIT;
