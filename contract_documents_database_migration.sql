-- First-class document records for employee contracts.
CREATE TABLE IF NOT EXISTS public.contract_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id UUID NOT NULL REFERENCES public.contracts(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,
    document_type TEXT NOT NULL DEFAULT 'contract_attachment',
    uploaded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (contract_id, file_url)
);

CREATE INDEX IF NOT EXISTS contract_documents_contract_idx ON public.contract_documents(contract_id, created_at DESC);
ALTER TABLE public.contract_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Contract parties can view contract documents" ON public.contract_documents;
CREATE POLICY "Contract parties can view contract documents"
ON public.contract_documents FOR SELECT TO authenticated
USING (
    employee_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.profiles viewer
        WHERE viewer.id = auth.uid()
          AND (UPPER(COALESCE(viewer.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
               OR UPPER(TRIM(COALESCE(viewer.job_title, ''))) = 'HR MANAGER')
    )
);

DROP POLICY IF EXISTS "HR and Admin can manage contract documents" ON public.contract_documents;
CREATE POLICY "HR and Admin can manage contract documents"
ON public.contract_documents FOR ALL TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles viewer
        WHERE viewer.id = auth.uid()
          AND (UPPER(COALESCE(viewer.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
               OR UPPER(TRIM(COALESCE(viewer.job_title, ''))) = 'HR MANAGER')
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.profiles viewer
        WHERE viewer.id = auth.uid()
          AND (UPPER(COALESCE(viewer.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
               OR UPPER(TRIM(COALESCE(viewer.job_title, ''))) = 'HR MANAGER')
    )
);

-- Preserve all previously uploaded confidentiality-policy URLs.
INSERT INTO public.contract_documents(contract_id, employee_id, file_name, file_url, document_type, uploaded_by)
SELECT contract.id, contract.employee_id,
       COALESCE(NULLIF(regexp_replace(split_part(contract.confidentiality_policy_url, '/', -1), '^[0-9]+-', ''), ''), 'Company Policy and Regulations'),
       contract.confidentiality_policy_url, 'confidentiality_policy', NULL
FROM public.contracts contract
WHERE NULLIF(BTRIM(contract.confidentiality_policy_url), '') IS NOT NULL
ON CONFLICT (contract_id, file_url) DO NOTHING;

NOTIFY pgrst, 'reload schema';
