BEGIN;

CREATE OR REPLACE FUNCTION public.validate_short_leave_request()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    IF NEW.leave_type='Short Leave' THEN
        IF NEW.short_leave_reason NOT IN (
            'I am running late to the office.',
            'I will be out for a meeting.',
            'I need to attend an urgent family matter.',
            'I have an important outing to run.'
        ) THEN RAISE EXCEPTION 'Select a valid short leave reason'; END IF;
        IF NEW.short_leave_duration_minutes NOT IN (15,60,120,180,1440) THEN
            RAISE EXCEPTION 'Short leave duration must be 15, 60, 120, 180 or 1440 minutes';
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

NOTIFY pgrst,'reload schema';
COMMIT;
