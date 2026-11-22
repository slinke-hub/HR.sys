-- Let CRM attachment uploaders delete their own stored objects. CRM leadership
-- retains its existing organization-wide deletion capability.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
BEGIN
  IF to_regprocedure('public.can_delete_crm_deal(uuid)') IS NULL
     OR to_regprocedure('public.delete_crm_deal_attachment_secure(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CRM attachment deletion functions are unavailable';
  END IF;
END
$guard$;

DROP POLICY IF EXISTS crm_deal_files_privileged_delete ON storage.objects;
DROP POLICY IF EXISTS crm_deal_files_delete_uploader_or_privileged ON storage.objects;
CREATE POLICY crm_deal_files_delete_uploader_or_privileged
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'crm-deal-files'
  AND (owner = auth.uid() OR public.can_delete_crm_deal(auth.uid()))
);

DO $verify$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'crm_deal_files_delete_uploader_or_privileged'
      AND cmd = 'DELETE' AND roles = ARRAY['authenticated']::name[]
      AND qual LIKE '%owner = auth.uid()%'
      AND qual LIKE '%can_delete_crm_deal%'
  ) THEN
    RAISE EXCEPTION 'CRM attachment storage deletion policy verification failed';
  END IF;
  IF has_function_privilege('anon', 'public.delete_crm_deal_attachment_secure(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.delete_crm_deal_attachment_secure(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CRM attachment deletion RPC grants are invalid';
  END IF;
END
$verify$;

NOTIFY pgrst, 'reload schema';
COMMIT;
