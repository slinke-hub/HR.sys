-- Repair the employee document update trigger left behind by the legacy
-- verification workflow. The removed workflow referenced columns that are not
-- present on employee_documents, causing every app edit to fail.

BEGIN;

CREATE OR REPLACE FUNCTION public.protect_employee_document_system_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND
       (to_jsonb(NEW) - ARRAY[
           'doc_name',
           'owner_name',
           'owner_email',
           'responsible_name',
           'responsible_email',
           'expiration_date',
           'owner_phone'
       ]::TEXT[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY[
           'doc_name',
           'owner_name',
           'owner_email',
           'responsible_name',
           'responsible_email',
           'expiration_date',
           'owner_phone'
       ]::TEXT[]) THEN
        RAISE EXCEPTION 'System-managed document fields cannot be changed from the app'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.protect_employee_document_system_fields() FROM PUBLIC;

DROP TRIGGER IF EXISTS protect_employee_document_system_fields_trigger
    ON public.employee_documents;

CREATE TRIGGER protect_employee_document_system_fields_trigger
BEFORE UPDATE ON public.employee_documents
FOR EACH ROW
EXECUTE FUNCTION public.protect_employee_document_system_fields();

COMMIT;
