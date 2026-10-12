-- Read-only staging verification. Raises on missing/unsafe state.
DO $$
DECLARE rls_enabled boolean; t text; required text[] := ARRAY['profiles','departments','job_titles','tasks','task_lists','task_comments','task_attachments','task_activity','projects','project_updates','project_todos','crm_clients','crm_deals','crm_deal_attachments','notifications','requests'];
BEGIN
  FOREACH t IN ARRAY required LOOP
    IF to_regclass('public.'||t) IS NULL THEN RAISE EXCEPTION 'Missing required table public.%', t; END IF;
  END LOOP;
  FOREACH t IN ARRAY ARRAY['profiles','tasks','task_comments','task_attachments','projects','project_updates','project_todos','crm_clients','crm_deals','crm_deal_attachments','notifications','requests'] LOOP
    SELECT c.relrowsecurity INTO rls_enabled FROM pg_class c WHERE c.oid = to_regclass('public.'||t);
    IF NOT COALESCE(rls_enabled,false) THEN RAISE EXCEPTION 'RLS is not enabled on public.%', t; END IF;
  END LOOP;
  FOREACH t IN ARRAY ARRAY['list_accessible_tasks_secure','get_task_secure','create_task_secure','update_task_secure','delete_task_secure','assign_task','change_task_status','add_task_comment','list_task_comments_secure','register_task_attachment','list_task_attachments_secure','remove_task_attachment','list_task_activity_secure','create_project_secure','update_project_secure','delete_project_secure','get_project_detail_secure','list_project_updates_secure','list_project_todos_secure','storage_object_metadata_allowed','can_read_contract_document_file','can_manage_contract_document_file','can_read_hr_document_file','can_manage_hr_document_file','can_upload_task_attachment_file','list_contract_documents_secure','get_contract_document_secure','register_contract_document_secure','delete_contract_document_secure','list_my_notifications','get_my_notification','get_my_unread_notification_count','mark_notification_read','mark_all_notifications_read','delete_my_notification','create_notification_secure','register_notification_device','update_notification_device_token','unregister_notification_device','list_my_notification_devices'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='public' AND p.proname=t) THEN RAISE EXCEPTION 'Missing required RPC/function public.%', t; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='Users can read their own notifications') THEN
    RAISE EXCEPTION 'Notification read policy is missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='Users can manage their own notifications') THEN
    RAISE EXCEPTION 'Broad notification policy is still present';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants WHERE table_schema='public' AND table_name='notifications' AND grantee='authenticated' AND privilege_type IN ('INSERT','UPDATE','DELETE')) THEN
    RAISE EXCEPTION 'Authenticated notification table writes are still granted';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants WHERE table_schema='public' AND table_name='push_subscriptions' AND grantee='authenticated' AND privilege_type IN ('INSERT','UPDATE','DELETE','SELECT')) THEN
    RAISE EXCEPTION 'Authenticated push-subscription table access is still granted';
  END IF;
  IF (SELECT count(*) FROM storage.buckets WHERE id IN ('task-attachments','contract-documents','crm-deal-files','hr-documents') AND public=false AND file_size_limit=26214400 AND 'application/pdf' = ANY(allowed_mime_types) AND 'image/png' = ANY(allowed_mime_types)) <> 4 THEN RAISE EXCEPTION 'Private storage buckets or upload limits are incomplete'; END IF;
  FOREACH t IN ARRAY ARRAY['sensitive_task_attachments_read','sensitive_crm_deal_files_read','sensitive_contract_documents_read','sensitive_hr_documents_read','task_attachment_storage_insert_secure','contract_documents_storage_insert_secure','hr_documents_storage_insert_secure'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname=t) THEN RAISE EXCEPTION 'Missing storage policy %', t; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='sensitive_hr_documents_read' AND qual::text ILIKE '%USING (bucket_id = ''hr-documents'')%') THEN
    RAISE EXCEPTION 'HR document storage policy is still globally readable';
  END IF;
  IF (SELECT count(*) FROM public.profiles WHERE COALESCE(employee_id, '') NOT IN ('TEST-MANAGER','TEST-EMPLOYEE','TEST-OUTSIDER')) <> 0
     OR (SELECT count(*) FROM public.tasks) <> 0
     OR (SELECT count(*) FROM public.projects) <> 0
     OR (SELECT count(*) FROM public.crm_clients) <> 0
     OR (SELECT count(*) FROM public.crm_deals) <> 0
     OR (SELECT count(*) FROM public.requests) <> 0
     OR (SELECT count(*) FROM public.contracts) <> 0
     OR (SELECT count(*) FROM public.employee_documents) <> 0
     OR (SELECT count(*) FROM storage.objects WHERE bucket_id IN ('task-attachments','contract-documents','crm-deal-files','hr-documents')) <> 0 THEN
    RAISE EXCEPTION 'Production application rows or attachment objects were copied into staging';
  END IF;
END $$;

SELECT 'staging_ref' AS check, current_setting('app.settings.project_ref', true) AS value
UNION ALL SELECT 'profiles', count(*)::text FROM public.profiles
UNION ALL SELECT 'tasks', count(*)::text FROM public.tasks
UNION ALL SELECT 'projects', count(*)::text FROM public.projects
UNION ALL SELECT 'crm_clients', count(*)::text FROM public.crm_clients
UNION ALL SELECT 'crm_deals', count(*)::text FROM public.crm_deals;
