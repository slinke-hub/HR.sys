-- Sensitive HR and CRM files must never use permanent public object URLs.
BEGIN;

UPDATE storage.buckets
SET public = false
WHERE id IN ('task-attachments', 'contract-documents', 'crm-deal-files', 'hr-documents');

DROP POLICY IF EXISTS "Anyone can read CRM deal files" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload CRM deal files" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can read contract documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can read task attachments" ON storage.objects;

DROP POLICY IF EXISTS sensitive_crm_deal_files_read ON storage.objects;
CREATE POLICY sensitive_crm_deal_files_read
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'crm-deal-files'
    AND public.can_access_crm(auth.uid())
);

DROP POLICY IF EXISTS sensitive_crm_deal_files_insert ON storage.objects;
CREATE POLICY sensitive_crm_deal_files_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'crm-deal-files'
    AND owner = auth.uid()
    AND public.can_access_crm(auth.uid())
);

DROP POLICY IF EXISTS sensitive_contract_documents_read ON storage.objects;
CREATE POLICY sensitive_contract_documents_read
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'contract-documents'
    AND (
        public.can_manage_employee_contracts(auth.uid())
        OR (storage.foldername(name))[1] = auth.uid()::text
    )
);

DROP POLICY IF EXISTS sensitive_task_attachments_read ON storage.objects;
CREATE POLICY sensitive_task_attachments_read
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'task-attachments'
    AND (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    AND EXISTS (
        SELECT 1
        FROM public.tasks task
        WHERE task.id = ((storage.foldername(name))[1])::uuid
    )
);

-- Legacy edit-task uploads did not include the task id in the object path.
-- They remain available to signed-in users, but never through public URLs.
DROP POLICY IF EXISTS sensitive_hr_documents_read ON storage.objects;
CREATE POLICY sensitive_hr_documents_read
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'hr-documents');

COMMIT;
