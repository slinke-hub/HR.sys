BEGIN;
DROP POLICY IF EXISTS crm_deal_files_privileged_delete ON storage.objects;
CREATE POLICY crm_deal_files_privileged_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'crm-deal-files' AND public.can_delete_crm_deal(auth.uid()));

DROP POLICY IF EXISTS sensitive_crm_deal_files_read ON storage.objects;
CREATE POLICY sensitive_crm_deal_files_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'crm-deal-files' AND (public.can_access_crm(auth.uid()) OR EXISTS (
  SELECT 1 FROM public.crm_deal_attachments attachment
  JOIN public.projects project ON project.deal_id = attachment.deal_id
  WHERE attachment.file_url = 'storage://crm-deal-files/' || storage.objects.name
    AND attachment.is_archived = false AND attachment.visible_to_project_assignee = true
    AND auth.uid() = ANY(COALESCE(project.assigned_people, ARRAY[]::uuid[]))
)));

DROP POLICY IF EXISTS sensitive_crm_deal_files_insert ON storage.objects;
CREATE POLICY sensitive_crm_deal_files_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'crm-deal-files' AND public.can_access_crm(auth.uid())
  AND public.storage_object_metadata_allowed(bucket_id, name, coalesce(metadata, '{}'::jsonb)));

DROP POLICY IF EXISTS sensitive_contract_documents_read ON storage.objects;
CREATE POLICY sensitive_contract_documents_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'contract-documents' AND public.can_read_contract_document_file(name, auth.uid()));

DROP POLICY IF EXISTS sensitive_hr_documents_read ON storage.objects;
CREATE POLICY sensitive_hr_documents_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'hr-documents' AND public.can_read_hr_document_file(name, auth.uid()));

DROP POLICY IF EXISTS sensitive_task_attachments_read ON storage.objects;
CREATE POLICY sensitive_task_attachments_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'task-attachments' AND EXISTS (
  SELECT 1 FROM public.task_attachments attachment
  LEFT JOIN public.tasks task ON task.id = attachment.task_id
  LEFT JOIN public.projects project ON project.id = task.project_id
  WHERE attachment.file_url = 'storage://task-attachments/' || storage.objects.name
    AND (public.can_access_task(task.id, auth.uid()) OR (project.id IS NOT NULL AND auth.uid() = ANY(COALESCE(project.assigned_people, ARRAY[]::uuid[]))))
));

DROP POLICY IF EXISTS task_attachment_storage_insert_secure ON storage.objects;
CREATE POLICY task_attachment_storage_insert_secure ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='task-attachments' AND public.can_upload_task_attachment_file(name, auth.uid())
  AND public.storage_object_metadata_allowed(bucket_id, name, coalesce(metadata, '{}'::jsonb)));
DROP POLICY IF EXISTS task_attachment_storage_update_secure ON storage.objects;
CREATE POLICY task_attachment_storage_update_secure ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id='task-attachments' AND (storage.foldername(name))[2] = auth.uid()::text AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' AND public.can_manage_task_attachments(((storage.foldername(name))[1])::uuid, auth.uid()))
WITH CHECK (bucket_id='task-attachments' AND (storage.foldername(name))[2] = auth.uid()::text AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' AND public.can_manage_task_attachments(((storage.foldername(name))[1])::uuid, auth.uid()));
DROP POLICY IF EXISTS task_attachment_storage_delete_secure ON storage.objects;
CREATE POLICY task_attachment_storage_delete_secure ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='task-attachments' AND (storage.foldername(name))[2] = auth.uid()::text AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$' AND public.can_manage_task_attachments(((storage.foldername(name))[1])::uuid, auth.uid()));
COMMIT;
