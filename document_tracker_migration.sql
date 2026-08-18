-- Document expiry tracker fields for the Documents page.
-- Run this once in the Supabase SQL Editor before using the new form.

BEGIN;

CREATE SEQUENCE IF NOT EXISTS public.employee_documents_document_id_seq;

ALTER TABLE public.employee_documents
    ADD COLUMN IF NOT EXISTS document_id BIGINT,
    ADD COLUMN IF NOT EXISTS owner_name TEXT,
    ADD COLUMN IF NOT EXISTS owner_email TEXT,
    ADD COLUMN IF NOT EXISTS responsible_name TEXT,
    ADD COLUMN IF NOT EXISTS responsible_email TEXT,
    ADD COLUMN IF NOT EXISTS expiration_date DATE,
    ADD COLUMN IF NOT EXISTS notified_30_days BOOLEAN DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS owner_phone TEXT;

-- The tracker replaces the old file/type inputs, while retaining legacy data.
ALTER TABLE public.employee_documents
    ALTER COLUMN doc_type DROP NOT NULL,
    ALTER COLUMN doc_base64 DROP NOT NULL;

ALTER SEQUENCE public.employee_documents_document_id_seq
    OWNED BY public.employee_documents.document_id;

ALTER TABLE public.employee_documents
    ALTER COLUMN document_id SET DEFAULT nextval('public.employee_documents_document_id_seq'::regclass);

UPDATE public.employee_documents
SET document_id = nextval('public.employee_documents_document_id_seq'::regclass)
WHERE document_id IS NULL;

SELECT setval(
    'public.employee_documents_document_id_seq'::regclass,
    COALESCE((SELECT MAX(document_id) FROM public.employee_documents), 0) + 1,
    FALSE
);

ALTER TABLE public.employee_documents
    ALTER COLUMN document_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS employee_documents_document_id_idx
    ON public.employee_documents(document_id);

UPDATE public.employee_documents
SET notified_30_days = TRUE
WHERE notified_30_days IS DISTINCT FROM TRUE;

ALTER TABLE public.employee_documents
    ALTER COLUMN notified_30_days SET DEFAULT TRUE,
    ALTER COLUMN notified_30_days SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'employee_documents_notified_30_days_true'
          AND conrelid = 'public.employee_documents'::regclass
    ) THEN
        ALTER TABLE public.employee_documents
            ADD CONSTRAINT employee_documents_notified_30_days_true
            CHECK (notified_30_days = TRUE);
    END IF;
END $$;

GRANT USAGE, SELECT ON SEQUENCE public.employee_documents_document_id_seq TO authenticated;

COMMIT;
