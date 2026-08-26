-- Automatically retain ended employment contracts in the archive.
BEGIN;

ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

ALTER TABLE public.contracts DROP CONSTRAINT IF EXISTS contracts_status_check;
ALTER TABLE public.contracts ADD CONSTRAINT contracts_status_check
    CHECK (status IN ('Draft', 'Pending Review', 'Pending Employee Approval', 'Active', 'Rejected', 'Expired', 'Terminated', 'Resigned', 'Cancelled'));

CREATE OR REPLACE FUNCTION public.archive_ended_employment_contract()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF LOWER(BTRIM(COALESCE(NEW.status, ''))) IN ('terminated', 'resigned') THEN
        NEW.is_archived := TRUE;
        NEW.archived_at := COALESCE(NEW.archived_at, NOW());
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS archive_ended_employment_contract_trigger ON public.contracts;
CREATE TRIGGER archive_ended_employment_contract_trigger
BEFORE INSERT OR UPDATE OF status ON public.contracts
FOR EACH ROW
EXECUTE FUNCTION public.archive_ended_employment_contract();

UPDATE public.contracts
SET is_archived = TRUE,
    archived_at = COALESCE(archived_at, updated_at, created_at, NOW())
WHERE LOWER(BTRIM(COALESCE(status, ''))) IN ('terminated', 'resigned')
  AND is_archived IS DISTINCT FROM TRUE;

NOTIFY pgrst, 'reload schema';
COMMIT;
