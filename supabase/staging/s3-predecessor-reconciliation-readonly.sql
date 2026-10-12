-- Read-only catalog reconciliation for the ten migrations preceding S3.
-- Run only against staging jcfyyxsuspukcmybyhjj. No application rows are read.
-- Output is a compact JSON object; each result also carries VERSION|STATE|DETAIL.
WITH
proc AS (
  SELECT p.oid, n.nspname, p.proname,
         pg_catalog.pg_get_functiondef(p.oid) AS definition,
         p.prosecdef,
         coalesce(array_to_string(p.proconfig, ';'), '') AS config,
         pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
         pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
         coalesce((SELECT bool_or(x.grantee = 0 AND x.privilege_type = 'EXECUTE')
                   FROM pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) AS x), false) AS public_exec
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f'
),
objects AS (
  SELECT
    to_regclass('public.push_subscriptions') AS push_subscriptions,
    to_regclass('public.notifications') AS notifications,
    to_regclass('public.crm_clients') AS crm_clients,
    to_regclass('public.crm_deals') AS crm_deals,
    to_regclass('public.crm_deal_activity') AS crm_deal_activity,
    to_regclass('public.crm_deal_attachments') AS crm_deal_attachments,
    to_regclass('public.contract_documents') AS contract_documents,
    to_regclass('public.task_attachments') AS task_attachments,
    to_regclass('public.tasks') AS tasks,
    to_regclass('public.task_waiting_history') AS task_waiting_history,
    to_regclass('public.task_blocker_history') AS task_blocker_history,
    to_regclass('public.task_dependencies') AS task_dependencies,
    to_regclass('public.projects') AS projects
),
checks AS (
  SELECT * FROM (VALUES
    -- Notification service: schema, row-scoped policies, function contracts and ACLs.
    ('20260928120000', 'push platform column/type/default',
      (SELECT EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=o.push_subscriptions AND a.attname='platform' AND a.atttypid='text'::regtype AND NOT a.attisdropped)
       AND EXISTS (SELECT 1 FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum WHERE d.adrelid=o.push_subscriptions AND a.attname='platform' AND pg_get_expr(d.adbin,d.adrelid) LIKE '%web%') FROM objects o), false),
    ('20260928120000', 'push device columns and platform constraint',
      (SELECT (SELECT count(*)=3 FROM pg_attribute a WHERE a.attrelid=o.push_subscriptions AND a.attname IN ('push_token','device_name','app_version') AND NOT a.attisdropped)
       AND EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid=o.push_subscriptions AND c.conname='push_subscriptions_platform_check') FROM objects o), false),
    ('20260928120000', 'notification/push owner policies',
      EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='Users can read their own notifications' AND cmd='SELECT' AND qual ILIKE '%auth.uid%')
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='Users can read their own push subscriptions' AND cmd='SELECT' AND qual ILIKE '%auth.uid%')
      AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='notifications' AND c.relrowsecurity)
      AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='push_subscriptions' AND c.relrowsecurity), false),
    ('20260928120000', 'notification RPCs, invoker/definer and execution ACLs',
      (SELECT count(*)=11 AND bool_and(auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
       FROM proc WHERE oid IN (to_regprocedure('public.list_my_notifications(integer,timestamp with time zone,boolean)'),to_regprocedure('public.get_my_notification(uuid)'),to_regprocedure('public.get_my_unread_notification_count()'),to_regprocedure('public.mark_notification_read(uuid)'),to_regprocedure('public.mark_all_notifications_read()'),to_regprocedure('public.delete_my_notification(uuid)'),to_regprocedure('public.create_notification_secure(uuid,text,uuid)'),to_regprocedure('public.register_notification_device(text,text,text,text,text,text,text,uuid)'),to_regprocedure('public.update_notification_device_token(uuid,text)'),to_regprocedure('public.unregister_notification_device(uuid)'),to_regprocedure('public.list_my_notification_devices()'))), false),
    ('20260928120000', 'notification table grants are read-only to authenticated',
      has_table_privilege('authenticated','public.notifications','SELECT') AND NOT has_table_privilege('authenticated','public.notifications','INSERT') AND NOT has_table_privilege('authenticated','public.notifications','UPDATE') AND NOT has_table_privilege('authenticated','public.notifications','DELETE')
      AND NOT has_table_privilege('authenticated','public.push_subscriptions','SELECT') AND NOT has_table_privilege('authenticated','public.push_subscriptions','INSERT') AND NOT has_table_privilege('authenticated','public.push_subscriptions','UPDATE') AND NOT has_table_privilege('authenticated','public.push_subscriptions','DELETE'), false),

    -- Admin-auth service contracts.
    ('20260930100000', 'admin credential RPCs and authorization/search-path markers',
      (SELECT count(*)=4 AND bool_and(prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, auth%')
       FROM proc WHERE oid IN (to_regprocedure('public.admin_get_user_email(uuid)'),to_regprocedure('public.admin_update_user_credentials(uuid,text,text)'),to_regprocedure('public.admin_reset_user_password(uuid,text)'),to_regprocedure('public.admin_set_user_lock(uuid,boolean)')))
      AND (SELECT bool_and(definition ILIKE '%auth.uid()%' AND definition ILIKE '%role%ADMIN%' AND definition ILIKE '%is_active%') FROM proc WHERE oid IN (to_regprocedure('public.admin_get_user_email(uuid)'),to_regprocedure('public.admin_update_user_credentials(uuid,text,text)'),to_regprocedure('public.admin_reset_user_password(uuid,text)'),to_regprocedure('public.admin_set_user_lock(uuid,boolean)'))), false),
    ('20260930100000', 'legacy reset_user_password execution revoked',
      to_regprocedure('public.reset_user_password(uuid,text)') IS NOT NULL AND NOT has_function_privilege('authenticated',to_regprocedure('public.reset_user_password(uuid,text)'),'EXECUTE') AND NOT has_function_privilege('anon',to_regprocedure('public.reset_user_password(uuid,text)'),'EXECUTE'), false),

    -- Client secure facade, satisfied by Phase 1's later facade rename/wrapper.
    ('20260930101000', 'Client secure facade signatures and latest Phase 1 wrapper',
      (SELECT count(*)=6 AND bool_and(prosecdef AND NOT anon_exec AND NOT public_exec)
       FROM proc WHERE oid IN (to_regprocedure('public.crm_client_dto(public.crm_clients)'),to_regprocedure('public.list_crm_clients_secure(text)'),to_regprocedure('public.get_crm_client_secure(uuid)'),to_regprocedure('public.create_crm_client_secure(jsonb)'),to_regprocedure('public.update_crm_client_secure(uuid,jsonb)'),to_regprocedure('public.delete_crm_client_secure(uuid)')))
      AND NOT has_function_privilege('authenticated',to_regprocedure('public.crm_client_dto(public.crm_clients)'),'EXECUTE')
      AND has_function_privilege('authenticated',to_regprocedure('public.list_crm_clients_secure(text)'),'EXECUTE')
      AND has_function_privilege('authenticated',to_regprocedure('public.get_crm_client_secure(uuid)'),'EXECUTE')
      AND has_function_privilege('authenticated',to_regprocedure('public.create_crm_client_secure(jsonb)'),'EXECUTE')
      AND has_function_privilege('authenticated',to_regprocedure('public.update_crm_client_secure(uuid,jsonb)'),'EXECUTE')
      AND has_function_privilege('authenticated',to_regprocedure('public.delete_crm_client_secure(uuid)'),'EXECUTE')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') AND prosecdef AND NOT auth_exec AND NOT anon_exec AND NOT public_exec)
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_crm_client_secure(uuid)') AND definition ILIKE '%project_operational_snapshot%'), false),
    ('20260930101000', 'Client table direct-write restriction and secure read policy',
      has_table_privilege('authenticated','public.crm_clients','SELECT') AND NOT has_table_privilege('authenticated','public.crm_clients','INSERT') AND NOT has_table_privilege('authenticated','public.crm_clients','UPDATE') AND NOT has_table_privilege('authenticated','public.crm_clients','DELETE')
      AND NOT has_table_privilege('anon','public.crm_clients','SELECT')
      AND NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='crm_clients' AND policyname IN ('Users can view clients','Users can insert clients','Users can update clients','Users can delete clients')), false),

    -- Deal services and private storage authorization policies.
    ('20260930102000', 'Deal RPC signatures and grants',
      (SELECT count(*)=10 AND bool_and(prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
       FROM proc WHERE oid IN (to_regprocedure('public.get_crm_deal_secure(uuid)'),to_regprocedure('public.create_crm_deal_secure(jsonb)'),to_regprocedure('public.update_crm_deal_secure(uuid,jsonb)'),to_regprocedure('public.assign_crm_deal_secure(uuid,uuid)'),to_regprocedure('public.list_crm_deal_activity_secure(uuid)'),to_regprocedure('public.list_crm_deal_attachments_secure(uuid)'),to_regprocedure('public.get_crm_deal_attachment_secure(uuid)'),to_regprocedure('public.register_crm_deal_attachment_secure(uuid,text,text,text,text,text,bigint,boolean)'),to_regprocedure('public.delete_crm_deal_attachment_secure(uuid)'),to_regprocedure('public.log_crm_deal_activity_secure(uuid,text,text,text,text)'))), false),
    ('20260930102000', 'Deal table write revocations',
      NOT has_table_privilege('anon','public.crm_deals','SELECT') AND NOT has_table_privilege('authenticated','public.crm_deals','INSERT') AND NOT has_table_privilege('authenticated','public.crm_deals','UPDATE') AND NOT has_table_privilege('authenticated','public.crm_deals','DELETE')
      AND NOT has_table_privilege('authenticated','public.crm_deal_activity','INSERT') AND NOT has_table_privilege('authenticated','public.crm_deal_attachments','DELETE'), false),
    ('20260930102000', 'Deal/task Storage policies and access helpers',
      EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='sensitive_crm_deal_files_read' AND qual ILIKE '%can_read_crm_deal_file%')
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='sensitive_task_attachments_read' AND qual ILIKE '%can_read_task_attachment_file%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.can_read_crm_deal_file(text,uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.can_read_task_attachment_file(text,uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%'), false),
    ('20260930102000', 'legacy Deal conversion completion-safe façade',
      EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.create_project_from_won_deal_v2(uuid,jsonb)') AND auth_exec AND NOT anon_exec AND NOT public_exec)
      AND to_regprocedure('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)') IS NOT NULL
      AND NOT has_function_privilege('authenticated',to_regprocedure('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)'),'EXECUTE'), false),

    -- File services: current metadata helpers, contracts and HR storage policies.
    ('20260930103000', 'file RPC/helper signatures and ACLs',
      (SELECT count(*)=10 AND bool_and(prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
       FROM proc WHERE oid IN (to_regprocedure('public.storage_object_metadata_allowed(text,text,jsonb)'),to_regprocedure('public.can_read_contract_document_file(text,uuid)'),to_regprocedure('public.can_manage_contract_document_file(text,uuid)'),to_regprocedure('public.can_read_hr_document_file(text,uuid)'),to_regprocedure('public.can_manage_hr_document_file(text,uuid)'),to_regprocedure('public.can_upload_task_attachment_file(text,uuid)'),to_regprocedure('public.list_contract_documents_secure(uuid)'),to_regprocedure('public.register_contract_document_secure(uuid,uuid,text,text,text,text,bigint)'),to_regprocedure('public.get_contract_document_secure(uuid)'),to_regprocedure('public.delete_contract_document_secure(uuid)'))), false),
    ('20260930103000', 'document and HR Storage policies',
      (SELECT count(*)=8 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname IN ('sensitive_contract_documents_read','contract_documents_storage_insert_secure','contract_documents_storage_update_secure','contract_documents_storage_delete_secure','sensitive_hr_documents_read','hr_documents_storage_insert_secure','hr_documents_storage_update_secure','hr_documents_storage_delete_secure'))
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='sensitive_crm_deal_files_insert' AND with_check ILIKE '%storage_object_metadata_allowed%')
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='task_attachment_storage_insert_secure' AND with_check ILIKE '%can_upload_task_attachment_file%')
      AND has_table_privilege('authenticated','public.contract_documents','SELECT') AND NOT has_table_privilege('authenticated','public.contract_documents','INSERT') AND NOT has_table_privilege('authenticated','public.contract_documents','UPDATE') AND NOT has_table_privilege('authenticated','public.contract_documents','DELETE'), false),

    -- Phase A work states/history. Later Phase B retains these objects and replaces lifecycle functions.
    ('20260930104000', 'Phase A task columns, history tables/indexes and RLS',
      (SELECT (SELECT count(*)=12 FROM pg_attribute a WHERE a.attrelid=o.tasks AND a.attname IN ('work_state','started_at','completed_at','waiting_category','waiting_related_user_id','waiting_note','waiting_since','blocked_category','blocked_related_user_id','blocked_note','blocked_since','resume_status') AND NOT a.attisdropped)
      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=o.tasks AND a.attname='work_state' AND a.atttypid='text'::regtype AND a.attnotnull)
      AND EXISTS (SELECT 1 FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum WHERE d.adrelid=o.tasks AND a.attname='work_state' AND pg_get_expr(d.adbin,d.adrelid) ILIKE '%ACTIVE%')
      AND to_regclass('public.task_waiting_history') IS NOT NULL AND to_regclass('public.task_blocker_history') IS NOT NULL
      AND to_regclass('public.task_my_day_state_idx') IS NOT NULL AND to_regclass('public.task_waiting_history_task_idx') IS NOT NULL AND to_regclass('public.task_blocker_history_task_idx') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_class c WHERE c.oid=o.task_waiting_history AND c.relrowsecurity)
      AND EXISTS (SELECT 1 FROM pg_class c WHERE c.oid=o.task_blocker_history AND c.relrowsecurity)
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='task_waiting_history' AND policyname='task_waiting_history_secure_select' AND qual ILIKE '%can_access_task%')
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='task_blocker_history' AND policyname='task_blocker_history_secure_select' AND qual ILIKE '%can_access_task%')
      AND CASE WHEN o.task_waiting_history IS NOT NULL THEN NOT has_table_privilege('authenticated',o.task_waiting_history,'SELECT') ELSE false END
      AND CASE WHEN o.task_blocker_history IS NOT NULL THEN NOT has_table_privilege('authenticated',o.task_blocker_history,'SELECT') ELSE false END FROM objects o),
      EXISTS (SELECT 1 FROM pg_class c JOIN objects o ON c.oid=o.task_waiting_history WHERE NOT c.relrowsecurity)
      OR EXISTS (SELECT 1 FROM pg_class c JOIN objects o ON c.oid=o.task_blocker_history WHERE NOT c.relrowsecurity)),
    ('20260930104000', 'Phase A lifecycle latest-compatible RPCs',
      EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.start_task(uuid)') AND prosecdef AND definition ILIKE '%task_dependency_blocked%' AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.complete_task_productivity(uuid)') AND prosecdef AND definition ILIKE '%work_state%' AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.mark_task_waiting(uuid,text,uuid,text)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.mark_task_blocked(uuid,text,uuid,text)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.resume_task(uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%'), false),

    -- Phase B dependency schema/trigger and later-compatible Task RPC contracts.
    ('20260930105000', 'Phase B dependency table, indexes, trigger and RLS',
      (SELECT to_regclass('public.task_dependencies') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=o.tasks AND a.attname='dependency_ready_notified_at' AND a.atttypid='timestamp with time zone'::regtype AND NOT a.attisdropped)
      AND (SELECT count(*)=7 FROM pg_attribute a WHERE a.attrelid=o.task_dependencies AND a.attname IN ('id','predecessor_task_id','successor_task_id','created_by','created_at','removed_by','removed_at') AND NOT a.attisdropped)
      AND to_regclass('public.task_dependencies_predecessor_idx') IS NOT NULL AND to_regclass('public.task_dependencies_successor_idx') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid=o.task_dependencies AND t.tgname='task_dependency_context_guard' AND NOT t.tgisinternal)
      AND EXISTS (SELECT 1 FROM pg_class c WHERE c.oid=o.task_dependencies AND c.relrowsecurity)
      AND EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='task_dependencies' AND indexname='task_dependencies_active_pair_idx')
      AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='task_dependencies' AND policyname='task_dependencies_secure_select' AND qual ILIKE '%can_access_task%')
      AND CASE WHEN o.task_dependencies IS NOT NULL THEN NOT has_table_privilege('authenticated',o.task_dependencies,'SELECT') ELSE false END FROM objects o),
      EXISTS (SELECT 1 FROM pg_class c JOIN objects o ON c.oid=o.task_dependencies WHERE NOT c.relrowsecurity)
      OR (to_regclass('public.task_dependencies') IS NOT NULL AND (SELECT count(*)<7 FROM pg_attribute a WHERE a.attrelid=to_regclass('public.task_dependencies') AND a.attname IN ('id','predecessor_task_id','successor_task_id','created_by','created_at','removed_by','removed_at') AND NOT a.attisdropped))),
    ('20260930105000', 'Phase B dependency and completion RPC final contracts',
      (SELECT count(*)=6 AND bool_and(prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
       FROM proc WHERE oid IN (to_regprocedure('public.create_task_dependency(uuid,uuid)'),to_regprocedure('public.remove_task_dependency(uuid)'),to_regprocedure('public.list_task_dependencies_secure(uuid)'),to_regprocedure('public.list_task_dependency_history_secure(uuid)'),to_regprocedure('public.list_task_dependency_blockers_secure()'),to_regprocedure('public.complete_and_hand_off_task(uuid,uuid)')))
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.start_task(uuid)') AND prosecdef AND definition ILIKE '%task_dependency_blocked%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.resume_task(uuid)') AND prosecdef AND definition ILIKE '%task_dependency_blocked%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.complete_task_productivity(uuid)') AND prosecdef AND definition ILIKE '%task_dependency_blocked%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.change_task_status(uuid,text)') AND prosecdef)
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.list_accessible_tasks_secure()') AND prosecdef AND definition ILIKE '%can_access_task%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.task_dependency_blocked(uuid)') AND prosecdef AND NOT auth_exec AND NOT anon_exec AND NOT public_exec)
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.validate_task_dependency_context()') AND prosecdef AND NOT auth_exec AND NOT anon_exec AND NOT public_exec)
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.complete_and_hand_off_task(uuid,uuid)') AND definition ILIKE '%Free-form handoff is not available%'), false),

    -- Phase C Project service functions; Phase 1's later definitions are accepted as final state.
    ('20260930106000', 'Phase C command/attention/event and Phase 1 final Project health RPCs',
      EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.list_project_command_center(integer,boolean,integer)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.list_attention_needed(integer)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.list_upcoming_events(integer,integer)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_project_health(uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND definition ILIKE '%project_operational_snapshot%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_project_operational_summary(uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND definition ILIKE '%project_operational_snapshot%'), false),

    -- Project profile ordering fix; compare body marker, not reconstructed argument strings.
    ('20261001090000', 'Project profile directory deterministic ordering definition',
      EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.list_accessible_project_profiles()') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%' AND definition ILIKE '%emp_index%NULLS LAST%' AND definition ILIKE '%full_name%'), false),

    -- Phase 1 final Project/Client façade state.
    ('20261002090000', 'Phase 1 operational snapshot/readiness signatures and definitions',
      EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.project_operational_snapshot(uuid,uuid)') AND prosecdef AND NOT auth_exec AND NOT anon_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_project_completion_readiness(uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%' AND definition ILIKE '%NO_TASKS%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_project_operational_summary(uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%' AND definition ILIKE '%project_operational_snapshot%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_project_health(uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%' AND definition ILIKE '%project_operational_snapshot%'), false),
    ('20261002090000', 'Phase 1 Client facade transition and project RPC signatures',
      EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_crm_client_secure(uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%' AND definition ILIKE '%project_operational_snapshot%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') AND prosecdef AND NOT auth_exec AND NOT anon_exec)
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.create_project_secure(jsonb)') AND prosecdef AND auth_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.update_project_secure(uuid,jsonb)') AND prosecdef AND auth_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.list_accessible_projects_secure()') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.get_project_detail_secure(uuid)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%')
      AND EXISTS (SELECT 1 FROM proc WHERE oid=to_regprocedure('public.change_project_status(uuid,text)') AND prosecdef AND auth_exec AND NOT anon_exec AND NOT public_exec AND config ILIKE '%search_path=public, pg_temp%'), false),
    ('20261002090000', 'Phase 1 legacy Deal conversion revoke and Project table write boundary',
      to_regprocedure('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)') IS NOT NULL
      AND NOT has_function_privilege('authenticated',to_regprocedure('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)'),'EXECUTE')
      AND NOT has_function_privilege('anon',to_regprocedure('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)'),'EXECUTE')
      AND NOT has_table_privilege('authenticated','public.projects','INSERT') AND NOT has_table_privilege('authenticated','public.projects','UPDATE') AND NOT has_table_privilege('authenticated','public.projects','DELETE'), false)
  ) AS v(version, check_name, ok, conflict)
),
migration_rollup AS (
  SELECT version,
         count(*) AS checks_total,
         count(*) FILTER (WHERE ok) AS checks_passed,
         bool_or(conflict) AS has_conflict,
         string_agg(check_name || '=' || CASE WHEN ok THEN 'pass' ELSE 'fail' END, '; ' ORDER BY check_name) AS detail
  FROM checks
  GROUP BY version
),
classified_base AS (
  SELECT version,
         CASE WHEN has_conflict THEN 'CONFLICTING'
              WHEN checks_passed=checks_total THEN 'FULLY_PRESENT'
              WHEN checks_passed=0 THEN 'ABSENT'
              ELSE 'PARTIALLY_PRESENT' END AS state,
         detail,
         (NOT has_conflict AND checks_passed=checks_total) AS catalog_fully_present
  FROM migration_rollup
),
classified AS (
  SELECT b.version, b.state, b.detail,
         coalesce(h.recorded, false) AS history_recorded,
         (b.catalog_fully_present AND NOT coalesce(h.recorded, false)) AS safe_to_mark_history_applied
  FROM classified_base b
  LEFT JOIN LATERAL (
    SELECT EXISTS (
      SELECT 1 FROM supabase_migrations.schema_migrations sm
      WHERE sm.version = b.version
    ) AS recorded
  ) h ON true
),
summary AS (
  SELECT count(*) FILTER (WHERE state='FULLY_PRESENT') AS fully_present,
         count(*) FILTER (WHERE state='PARTIALLY_PRESENT') AS partially_present,
         count(*) FILTER (WHERE state='ABSENT') AS absent,
         count(*) FILTER (WHERE state='CONFLICTING') AS conflicting,
         coalesce(jsonb_agg(version ORDER BY version) FILTER (WHERE safe_to_mark_history_applied), '[]'::jsonb) AS safe_history_repair_candidates,
         coalesce(jsonb_agg(version ORDER BY version) FILTER (WHERE state='ABSENT'), '[]'::jsonb) AS migrations_requiring_real_application,
         coalesce(jsonb_agg(version ORDER BY version) FILTER (WHERE state IN ('PARTIALLY_PRESENT','CONFLICTING')), '[]'::jsonb) AS migrations_requiring_manual_review
  FROM classified
)
SELECT jsonb_build_object(
  'results', (SELECT jsonb_agg(jsonb_build_object(
      'version', version,
      'state', state,
      'detail', detail,
      'result_line', version || '|' || state || '|' || detail,
      'history_recorded', history_recorded,
      'SAFE_TO_MARK_HISTORY_APPLIED', safe_to_mark_history_applied,
      'safe_history_line', 'SAFE_TO_MARK_HISTORY_APPLIED|' || safe_to_mark_history_applied::text
    ) ORDER BY version) FROM classified),
  'summary', jsonb_build_object(
      'PRE_S3_FULLY_PRESENT', fully_present,
      'PRE_S3_PARTIALLY_PRESENT', partially_present,
      'PRE_S3_ABSENT', absent,
      'PRE_S3_CONFLICTING', conflicting,
      'SAFE_HISTORY_REPAIR_CANDIDATES', safe_history_repair_candidates,
      'MIGRATIONS_REQUIRING_REAL_APPLICATION', migrations_requiring_real_application,
      'MIGRATIONS_REQUIRING_MANUAL_REVIEW', migrations_requiring_manual_review
  )
) AS staging_predecessor_reconciliation
FROM summary;
