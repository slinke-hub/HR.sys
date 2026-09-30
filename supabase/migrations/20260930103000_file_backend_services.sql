-- Reviewed production migration generated from the verified service artifact.
-- Source artifact: file_backend_services.sql
-- No environment reference, test identity, synthetic fixture, or cleanup harness is included.
-- Files/attachments backend façade for HR.sys security production.
-- This artifact is intentionally reviewed production.  It never seeds application data.
-- All file objects remain private and are accessed through short-lived signed URLs.
BEGIN;

CREATE OR REPLACE FUNCTION public.storage_object_metadata_allowed(
  p_bucket text,
  p_object_name text,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mime text := lower(btrim(coalesce(p_metadata->>'mimetype', p_metadata->>'mimeType', '')));
  v_size_text text := coalesce(p_metadata->>'size', '');
  v_size bigint;
  v_name text := lower(coalesce(p_object_name, ''));
BEGIN
  IF p_bucket NOT IN ('task-attachments', 'contract-documents', 'crm-deal-files', 'hr-documents')
     OR v_name = '' OR v_name LIKE '%..%' OR position(chr(92) in v_name) > 0 THEN
    RETURN false;
  END IF;

  IF v_size_text <> '' THEN
    IF v_size_text !~ '^[0-9]+$' THEN RETURN false; END IF;
    v_size := v_size_text::bigint;
    IF v_size < 0 OR v_size > 26214400 THEN RETURN false; END IF;
  END IF;

  IF v_mime <> '' AND v_mime NOT IN (
    'application/pdf','image/jpeg','image/png','image/webp','text/plain',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ) THEN
    RETURN false;
  END IF;

  IF v_name ~ '\.(exe|com|bat|cmd|scr|js|vbs|ps1|sh|dll)(\.|$)' THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_read_contract_document_file(
  p_object_name text,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND (
      public.can_manage_employee_contracts(p_user_id)
      OR EXISTS (
        SELECT 1
        FROM public.contract_documents document
        WHERE document.file_url = 'storage://contract-documents/' || p_object_name
          AND document.employee_id = p_user_id
      )
      OR split_part(coalesce(p_object_name, ''), '/', 1) = p_user_id::text
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_contract_document_file(
  p_object_name text,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND public.can_manage_employee_contracts(p_user_id)
    AND split_part(coalesce(p_object_name, ''), '/', 1) ~* '^[0-9a-f-]{36}$'
    AND EXISTS (
      SELECT 1 FROM public.profiles employee
      WHERE employee.id = split_part(p_object_name, '/', 1)::uuid
        AND employee.is_active IS DISTINCT FROM false
    );
$$;

CREATE OR REPLACE FUNCTION public.can_read_hr_document_file(
  p_object_name text,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND (
      public.can_manage_employee_contracts(p_user_id)
      OR split_part(coalesce(p_object_name, ''), '/', 1) = p_user_id::text
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_hr_document_file(
  p_object_name text,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND (
      public.can_manage_employee_contracts(p_user_id)
      OR split_part(coalesce(p_object_name, ''), '/', 1) = p_user_id::text
    );
$$;

CREATE OR REPLACE FUNCTION public.can_upload_task_attachment_file(
  p_object_name text,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_task_id uuid;
  v_task_text text := split_part(coalesce(p_object_name, ''), '/', 1);
  v_uploader text := split_part(coalesce(p_object_name, ''), '/', 2);
BEGIN
  IF p_user_id IS NULL OR v_task_text !~* '^[0-9a-f-]{36}$' OR v_uploader <> p_user_id::text THEN
    RETURN false;
  END IF;
  v_task_id := v_task_text::uuid;
  RETURN public.can_manage_task_attachments(v_task_id, p_user_id);
END;
$$;

-- Contract document operations are the authoritative path for native clients.
CREATE OR REPLACE FUNCTION public.list_contract_documents_secure(p_contract_id uuid)
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT to_jsonb(document)
  FROM public.contract_documents document
  WHERE document.contract_id = p_contract_id
    AND (
      document.employee_id = auth.uid()
      OR public.can_manage_employee_contracts(auth.uid())
    )
  ORDER BY document.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.register_contract_document_secure(
  p_contract_id uuid,
  p_employee_id uuid,
  p_file_url text,
  p_file_name text,
  p_document_type text DEFAULT 'contract_attachment',
  p_file_type text DEFAULT NULL,
  p_file_size bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.contract_documents%ROWTYPE;
  v_url text := btrim(coalesce(p_file_url, ''));
  v_name text := btrim(coalesce(p_file_name, ''));
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_employee_contracts(auth.uid()) THEN
    RAISE EXCEPTION 'Contract document management is restricted' USING ERRCODE = '42501';
  END IF;
  IF p_contract_id IS NULL OR p_employee_id IS NULL OR v_name = '' THEN
    RAISE EXCEPTION 'Contract, employee, and file name are required' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.contracts contract
    WHERE contract.id = p_contract_id AND contract.employee_id = p_employee_id
  ) THEN
    RAISE EXCEPTION 'Contract does not belong to employee' USING ERRCODE = '42501';
  END IF;
  IF v_url !~ '^storage://contract-documents/[A-Za-z0-9._/-]+$' THEN
    RAISE EXCEPTION 'Invalid contract document storage reference' USING ERRCODE = '22023';
  END IF;
  IF split_part(replace(v_url, 'storage://contract-documents/', ''), '/', 1) <> p_employee_id::text THEN
    RAISE EXCEPTION 'Contract document path does not match employee' USING ERRCODE = '22023';
  END IF;
  IF p_file_size IS NOT NULL AND (p_file_size < 0 OR p_file_size > 26214400) THEN
    RAISE EXCEPTION 'Attachment exceeds the 25 MB limit' USING ERRCODE = '22023';
  END IF;
  IF lower(coalesce(p_file_type, '')) <> '' AND lower(p_file_type) NOT IN (
    'application/pdf','image/jpeg','image/png','image/webp','text/plain',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ) THEN
    RAISE EXCEPTION 'This file type is not allowed' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.contract_documents(contract_id, employee_id, file_name, file_url, document_type, uploaded_by)
  VALUES (p_contract_id, p_employee_id, v_name, v_url,
          coalesce(nullif(btrim(p_document_type), ''), 'contract_attachment'), auth.uid())
  ON CONFLICT (contract_id, file_url) DO UPDATE
    SET file_name = excluded.file_name,
        document_type = excluded.document_type,
        uploaded_by = auth.uid()
  RETURNING * INTO v_row;
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_contract_document_secure(p_document_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT to_jsonb(document)
  FROM public.contract_documents document
  WHERE document.id = p_document_id
    AND (document.employee_id = auth.uid() OR public.can_manage_employee_contracts(auth.uid()));
$$;

CREATE OR REPLACE FUNCTION public.delete_contract_document_secure(p_document_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_employee_contracts(auth.uid()) THEN
    RAISE EXCEPTION 'Contract document management is restricted' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.contract_documents WHERE id = p_document_id;
  RETURN FOUND;
END;
$$;

-- Replace broad/legacy object policies with parent-scoped private policies.
DROP POLICY IF EXISTS sensitive_contract_documents_read ON storage.objects;
CREATE POLICY sensitive_contract_documents_read ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'contract-documents' AND public.can_read_contract_document_file(name, auth.uid()));

DROP POLICY IF EXISTS contract_documents_storage_insert_secure ON storage.objects;
CREATE POLICY contract_documents_storage_insert_secure ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'contract-documents'
    AND public.can_manage_contract_document_file(name, auth.uid())
    AND public.storage_object_metadata_allowed(bucket_id, name, coalesce(metadata, '{}'::jsonb))
  );

DROP POLICY IF EXISTS contract_documents_storage_update_secure ON storage.objects;
CREATE POLICY contract_documents_storage_update_secure ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'contract-documents' AND public.can_manage_contract_document_file(name, auth.uid()))
  WITH CHECK (bucket_id = 'contract-documents' AND public.can_manage_contract_document_file(name, auth.uid())
    AND public.storage_object_metadata_allowed(bucket_id, name, coalesce(metadata, '{}'::jsonb)));

DROP POLICY IF EXISTS contract_documents_storage_delete_secure ON storage.objects;
CREATE POLICY contract_documents_storage_delete_secure ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'contract-documents' AND public.can_manage_contract_document_file(name, auth.uid()));

DROP POLICY IF EXISTS sensitive_hr_documents_read ON storage.objects;
CREATE POLICY sensitive_hr_documents_read ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'hr-documents' AND public.can_read_hr_document_file(name, auth.uid()));

DROP POLICY IF EXISTS hr_documents_storage_insert_secure ON storage.objects;
CREATE POLICY hr_documents_storage_insert_secure ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'hr-documents'
    AND public.can_manage_hr_document_file(name, auth.uid())
    AND public.storage_object_metadata_allowed(bucket_id, name, coalesce(metadata, '{}'::jsonb))
  );

DROP POLICY IF EXISTS hr_documents_storage_update_secure ON storage.objects;
CREATE POLICY hr_documents_storage_update_secure ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'hr-documents' AND public.can_manage_hr_document_file(name, auth.uid()))
  WITH CHECK (bucket_id = 'hr-documents' AND public.can_manage_hr_document_file(name, auth.uid())
    AND public.storage_object_metadata_allowed(bucket_id, name, coalesce(metadata, '{}'::jsonb)));

DROP POLICY IF EXISTS hr_documents_storage_delete_secure ON storage.objects;
CREATE POLICY hr_documents_storage_delete_secure ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'hr-documents' AND public.can_manage_hr_document_file(name, auth.uid()));

-- Apply the same server-side metadata checks to existing Task/Deal upload policies.
DROP POLICY IF EXISTS sensitive_crm_deal_files_insert ON storage.objects;
CREATE POLICY sensitive_crm_deal_files_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'crm-deal-files'
    AND public.can_access_crm(auth.uid())
    AND public.storage_object_metadata_allowed(bucket_id, name, coalesce(metadata, '{}'::jsonb))
  );

DROP POLICY IF EXISTS task_attachment_storage_insert_secure ON storage.objects;
CREATE POLICY task_attachment_storage_insert_secure ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'task-attachments'
    AND public.can_upload_task_attachment_file(name, auth.uid())
    AND public.storage_object_metadata_allowed(bucket_id, name, coalesce(metadata, '{}'::jsonb))
  );

REVOKE ALL ON FUNCTION public.storage_object_metadata_allowed(text,text,jsonb),
  public.can_read_contract_document_file(text,uuid), public.can_manage_contract_document_file(text,uuid),
  public.can_read_hr_document_file(text,uuid), public.can_manage_hr_document_file(text,uuid),
  public.can_upload_task_attachment_file(text,uuid),
  public.list_contract_documents_secure(uuid), public.get_contract_document_secure(uuid),
  public.register_contract_document_secure(uuid,uuid,text,text,text,text,bigint),
  public.delete_contract_document_secure(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.storage_object_metadata_allowed(text,text,jsonb),
  public.can_read_contract_document_file(text,uuid), public.can_manage_contract_document_file(text,uuid),
  public.can_read_hr_document_file(text,uuid), public.can_manage_hr_document_file(text,uuid),
  public.can_upload_task_attachment_file(text,uuid),
  public.list_contract_documents_secure(uuid), public.get_contract_document_secure(uuid),
  public.register_contract_document_secure(uuid,uuid,text,text,text,text,bigint),
  public.delete_contract_document_secure(uuid)
  TO authenticated;

-- Authenticated clients use the secure contract façade, not direct table writes.
REVOKE INSERT, UPDATE, DELETE ON public.contract_documents FROM authenticated;
GRANT SELECT ON public.contract_documents TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
