-- Two-step employee onboarding: account identity followed by contract details.
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS nationality VARCHAR(30) DEFAULT 'Saudi';

ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES public.departments(id),
    ADD COLUMN IF NOT EXISTS primary_workplace VARCHAR(255),
    ADD COLUMN IF NOT EXISTS weekly_rest_day VARCHAR(100) DEFAULT 'Friday, Saturday',
    ADD COLUMN IF NOT EXISTS confidentiality_policy_url TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('contract-documents', 'contract-documents', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

DROP POLICY IF EXISTS "Contract managers can upload contract documents" ON storage.objects;
CREATE POLICY "Contract managers can upload contract documents"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'contract-documents'
    AND EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(COALESCE(role, '')) = 'ADMIN'
              OR UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
          )
    )
);

DROP POLICY IF EXISTS "Authenticated users can read contract documents" ON storage.objects;
CREATE POLICY "Authenticated users can read contract documents"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'contract-documents');
