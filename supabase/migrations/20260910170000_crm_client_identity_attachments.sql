-- Store one or more client identity PDFs/images alongside CRM presentation files.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.crm_deal_attachments
    DROP CONSTRAINT IF EXISTS crm_deal_attachments_category_check;

ALTER TABLE public.crm_deal_attachments
    ADD CONSTRAINT crm_deal_attachments_category_check
    CHECK (category IN (
        'QUOTATION',
        'CLIENT_IDENTITY',
        'TECHNICAL_PRESENTATION',
        'PROPOSAL',
        'PHOTO',
        'OTHER'
    ));

NOTIFY pgrst, 'reload schema';
COMMIT;
