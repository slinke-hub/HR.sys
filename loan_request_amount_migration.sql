-- Add and validate SAR amounts for new loan requests.
BEGIN;

ALTER TABLE public.requests ADD COLUMN IF NOT EXISTS loan_amount NUMERIC(14,2);

CREATE OR REPLACE FUNCTION public.validate_loan_request_amount()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    IF lower(COALESCE(NEW.request_type,'')) ~ '^loan( request)?$'
       AND (NEW.loan_amount IS NULL OR NEW.loan_amount<=0) THEN
        RAISE EXCEPTION 'Loan amount must be greater than zero SAR';
    END IF;
    IF NOT (lower(COALESCE(NEW.request_type,'')) ~ '^loan( request)?$') THEN NEW.loan_amount:=NULL; END IF;
    RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS validate_loan_request_amount_trigger ON public.requests;
CREATE TRIGGER validate_loan_request_amount_trigger
BEFORE INSERT OR UPDATE OF request_type,loan_amount ON public.requests
FOR EACH ROW EXECUTE FUNCTION public.validate_loan_request_amount();

NOTIFY pgrst,'reload schema';
COMMIT;
