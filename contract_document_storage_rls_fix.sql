-- Repair contract document uploads for active Admin and HR Manager accounts.
INSERT INTO storage.buckets (id, name, public)
VALUES ('contract-documents', 'contract-documents', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

CREATE OR REPLACE FUNCTION public.can_manage_employee_contracts(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND COALESCE(profile.is_active, TRUE) = TRUE
          AND (
              UPPER(TRIM(COALESCE(profile.role, ''))) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
              OR UPPER(TRIM(COALESCE(profile.job_title, ''))) = 'HR MANAGER'
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_manage_employee_contracts(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_employee_contracts(UUID) TO authenticated;

DROP POLICY IF EXISTS "Contract managers can upload contract documents" ON storage.objects;
DROP POLICY IF EXISTS "Contract managers can update contract documents" ON storage.objects;
DROP POLICY IF EXISTS "Contract managers can delete contract documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can read contract documents" ON storage.objects;

CREATE POLICY "Contract managers can upload contract documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'contract-documents'
    AND public.can_manage_employee_contracts(auth.uid())
);

CREATE POLICY "Contract managers can update contract documents"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'contract-documents' AND public.can_manage_employee_contracts(auth.uid()))
WITH CHECK (bucket_id = 'contract-documents' AND public.can_manage_employee_contracts(auth.uid()));

CREATE POLICY "Contract managers can delete contract documents"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'contract-documents' AND public.can_manage_employee_contracts(auth.uid()));

CREATE POLICY "Authenticated users can read contract documents"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'contract-documents');

NOTIFY pgrst, 'reload schema';
