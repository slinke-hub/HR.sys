-- Align CRM deal persistence with the create/edit form without invalidating
-- incomplete legacy deals when their pipeline stage changes.
BEGIN;

ALTER TABLE public.crm_deals
    ALTER COLUMN amount DROP NOT NULL,
    ALTER COLUMN closing_date DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.enforce_crm_deal_contact_requirements()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    -- New deals must contain all required contact details. On legacy rows, run
    -- the same validation once any of these fields is intentionally changed;
    -- unrelated stage transitions remain possible until the deal is edited.
    IF TG_OP = 'INSERT'
       OR NEW.first_contact_date IS DISTINCT FROM OLD.first_contact_date
       OR NEW.contact_method IS DISTINCT FROM OLD.contact_method
       OR NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
        IF NEW.first_contact_date IS NULL THEN
            RAISE EXCEPTION 'First contact date is required' USING ERRCODE = '23514';
        END IF;
        IF NULLIF(BTRIM(NEW.contact_method), '') IS NULL THEN
            RAISE EXCEPTION 'Contact method is required' USING ERRCODE = '23514';
        END IF;
        IF NEW.assigned_to IS NULL THEN
            RAISE EXCEPTION 'Deal assignee is required' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_deal_contact_requirements ON public.crm_deals;
CREATE TRIGGER crm_deal_contact_requirements
BEFORE INSERT OR UPDATE ON public.crm_deals
FOR EACH ROW EXECUTE FUNCTION public.enforce_crm_deal_contact_requirements();

NOTIFY pgrst, 'reload schema';
COMMIT;
