-- Store and validate the requested number of days for new leave requests.
BEGIN;

ALTER TABLE public.requests ADD COLUMN IF NOT EXISTS number_of_days INTEGER;

CREATE OR REPLACE FUNCTION public.validate_leave_request_days()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    IF NEW.request_type='Leave Request' AND (NEW.number_of_days IS NULL OR NEW.number_of_days<=0) THEN
        RAISE EXCEPTION 'Number of leave days must be a positive whole number';
    END IF;
    IF NEW.request_type<>'Leave Request' THEN NEW.number_of_days:=NULL; END IF;
    RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS validate_leave_request_days_trigger ON public.requests;
CREATE TRIGGER validate_leave_request_days_trigger
BEFORE INSERT OR UPDATE OF request_type,number_of_days ON public.requests
FOR EACH ROW EXECUTE FUNCTION public.validate_leave_request_days();

NOTIFY pgrst,'reload schema';
COMMIT;
