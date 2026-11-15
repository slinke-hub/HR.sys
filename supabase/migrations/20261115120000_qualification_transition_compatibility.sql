-- Review candidate: no hosted execution authorized. Preserve each environment's workflow.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $migration$
DECLARE
  stage_oid oid := to_regprocedure('public.change_crm_deal_stage(uuid,text)');
  ensure_oid oid := to_regprocedure('public.ensure_crm_generated_task(uuid,text)');
  guard_oid oid := to_regprocedure('public.guard_crm_contact_discussion_task()');
  stage_md5 text;
  guard_md5 text;
  before_security jsonb;
  after_security jsonb;
  marketing_oid oid := to_regprocedure('public.enforce_marketing_design_review()');
  marketing_definition text;
  marketing_security jsonb;
  staging_case boolean := false;
  boundary_oid oid := to_regprocedure('public.enforce_mq20_task_service_boundaries()');
  boundary_definition text;
  boundary_security jsonb;
  generator_oid oid := to_regprocedure('public.create_crm_contact_discussion_task(uuid)');
  qualification_oid oid := to_regprocedure('public.create_crm_contact_discussion_on_qualification()');
  attachment_policy_oid oid;
  attachment_reader_oid oid := to_regprocedure('public.can_read_task_attachment_file(text,uuid)');
  attachment_reader_security jsonb;
  attachment_manager_oid oid := to_regprocedure('public.can_manage_task_attachments(uuid,uuid)');
  attachment_manager_definition text;
  attachment_manager_security jsonb;
BEGIN
  IF current_user <> 'postgres' OR current_database() <> 'postgres'
     OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
     OR stage_oid IS NULL OR guard_oid IS NULL OR boundary_oid IS NULL OR marketing_oid IS NULL
     OR generator_oid IS NULL OR qualification_oid IS NULL THEN
    RAISE EXCEPTION 'Unexpected database, role, version, or workflow functions';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid IN (stage_oid,guard_oid,marketing_oid,boundary_oid,generator_oid,qualification_oid)
    AND (p.proowner <> 'postgres'::regrole OR NOT p.prosecdef OR NOT coalesce('search_path=public, pg_temp'=ANY(p.proconfig),false)))
    OR NOT has_function_privilege('authenticated',stage_oid,'EXECUTE')
    OR has_function_privilege('anon',stage_oid,'EXECUTE')
    OR has_function_privilege('anon',generator_oid,'EXECUTE') OR has_function_privilege('authenticated',generator_oid,'EXECUTE')
    OR md5(replace(replace(pg_get_functiondef(generator_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> '36ff1ea84a09da820d13f9d94e5a4b93'
    OR md5(replace(replace(pg_get_functiondef(qualification_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> 'f57d221d3d89ca8d4b00ff5ad622cc68' THEN
    RAISE EXCEPTION 'Workflow function ownership, security settings, or stage grants differ';
  END IF;
  SELECT md5(pg_get_functiondef(stage_oid)), md5(replace(replace(pg_get_functiondef(guard_oid), E'\r\n', E'\n'), E'\r', E'\n')) INTO stage_md5, guard_md5;
  IF marketing_oid IS NULL OR md5(pg_get_functiondef(marketing_oid)) <> '4003147e3c2d965ba2c15cae0d787a51' THEN
    RAISE EXCEPTION 'Marketing review fingerprint differs from reviewed baseline';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass
    AND tgname='crm_contact_discussion_on_qualification' AND tgenabled='O' AND tgtype=17
    AND tgfoid=qualification_oid) THEN
    RAISE EXCEPTION 'Qualification generation trigger differs from reviewed baseline';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass
    AND tgname='crm_contact_discussion_task_guard' AND tgenabled='O' AND tgtype=23 AND tgfoid=guard_oid)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass
    AND tgname='enforce_marketing_design_review_trigger' AND tgenabled='O' AND tgtype=23 AND tgfoid=marketing_oid) THEN
    RAISE EXCEPTION 'Contact or Marketing review triggers differ from reviewed baseline';
  END IF;
  IF stage_md5='ecf85ecf33decad1b75be756c340d062' AND guard_md5='293cae319b36c4ed98d7e7a265afd04a' AND ensure_oid IS NULL THEN
    -- Production's existing function already updates the stage before the AFTER trigger.
    RAISE NOTICE 'Production baseline already has the required ordering';
  ELSIF stage_md5 <> '7bef68c79797335b40d3d98fd2bb5335' OR guard_md5 <> '3d2487cc0610bee3cbe9615be2fd1750'
     OR ensure_oid IS NULL OR md5(pg_get_functiondef(ensure_oid)) <> 'f4cf0fe7a527b44e5f4f51ca3b1b17bd' THEN
    RAISE EXCEPTION 'Stage workflow fingerprints do not match a reviewed baseline';
  ELSE
  staging_case := true;
  SELECT jsonb_build_array(proowner,prosecdef,proconfig,proacl) INTO before_security FROM pg_proc WHERE oid=stage_oid;
  EXECUTE replace(replace($ddl$
  CREATE OR REPLACE FUNCTION public.change_crm_deal_stage(p_deal_id uuid, p_new_stage text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
  AS $body$
  DECLARE v_deal public.crm_deals%ROWTYPE; v_stage text := UPPER(BTRIM(COALESCE(p_new_stage, ''))); v_task uuid;
  BEGIN
    IF auth.uid() IS NULL OR NOT COALESCE(public.can_access_crm(auth.uid()), false)
       OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_active IS DISTINCT FROM false) THEN
      RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
    END IF;
    IF v_stage NOT IN ('LEAD', 'QUALIFICATION', 'PITCH', 'PROPOSAL', 'LOST') THEN
      RAISE EXCEPTION 'Use the dedicated submission or order workflow' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
    IF v_stage IN ('PITCH', 'PROPOSAL') THEN
      RAISE EXCEPTION 'Submit the required presentation documents first' USING ERRCODE = '23514';
    END IF;
    IF v_deal.stage IS DISTINCT FROM v_stage THEN
      UPDATE public.crm_deals SET stage = v_stage WHERE id = p_deal_id;
      INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, actor_id)
        VALUES (p_deal_id, 'STAGE_CHANGED', v_deal.stage, v_stage, auth.uid());
    END IF;
    IF v_stage = 'QUALIFICATION' THEN
      -- The AFTER UPDATE trigger creates the task once the deal is qualified.
      -- For a retry on an already qualified deal, the reviewed helper is idempotent.
      v_task := public.create_crm_contact_discussion_task(p_deal_id);
    END IF;
    RETURN jsonb_build_object('deal_id', p_deal_id, 'from_stage', v_deal.stage, 'to_stage', v_stage, 'task_id', v_task, 'actor_id', auth.uid());
  END;
  $body$;
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  SELECT jsonb_build_array(proowner,prosecdef,proconfig,proacl) INTO after_security FROM pg_proc WHERE oid=stage_oid;
  IF before_security IS DISTINCT FROM after_security OR md5(replace(replace(pg_get_functiondef(guard_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> guard_md5
     OR md5(pg_get_functiondef(stage_oid)) <> 'a8264b38b7d76ee225803775fa6e4d32' THEN
    RAISE EXCEPTION 'Function ownership, security, grants, or guard changed unexpectedly';
  END IF;
  END IF;
  SELECT pg_get_functiondef(marketing_oid),jsonb_build_array(proowner,prosecdef,proconfig,proacl)
    INTO marketing_definition,marketing_security FROM pg_proc WHERE oid=marketing_oid;
  IF position('    is_designing := NEW.department' IN marketing_definition)=0 THEN
    RAISE EXCEPTION 'Marketing review insertion point missing';
  END IF;
  marketing_definition := replace(marketing_definition,
    '    is_designing := NEW.department',
    $insert$    IF NEW.crm_workflow_kind = 'CONTACT_DISCUSSION'
       AND NEW.department IS NULL AND NEW.sub_type IS NULL
       AND EXISTS (SELECT 1 FROM public.crm_generated_tasks m
                    WHERE m.task_id=NEW.id AND m.deal_id=NEW.crm_deal_id AND m.kind='CONTACT_DISCUSSION') THEN
        RETURN NEW;
    END IF;
    is_designing := NEW.department$insert$);
  EXECUTE marketing_definition;
  IF marketing_security IS DISTINCT FROM (SELECT jsonb_build_array(proowner,prosecdef,proconfig,proacl) FROM pg_proc WHERE oid=marketing_oid)
     OR md5(replace(replace(pg_get_functiondef(marketing_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> '5de3c67d0dfecfd1d0cef8e338cf482d'
     OR md5(replace(replace(pg_get_functiondef(guard_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> guard_md5 THEN
    RAISE EXCEPTION 'Marketing security metadata or Contact guard changed';
  END IF;
  IF staging_case THEN
    IF boundary_oid IS NULL OR md5(replace(replace(pg_get_functiondef(boundary_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> '17a3a44b5e04a47d9503f8a84ec2008e'
       OR to_regprocedure('hrsys_private.valid_mq20_task_context(uuid,text,text)') IS NULL
       OR md5(replace(replace(pg_get_functiondef('hrsys_private.valid_mq20_task_context(uuid,text,text)'::regprocedure), E'\r\n', E'\n'), E'\r', E'\n')) <> 'c33aee8ab568756e35d51715d94a5e35'
       OR (SELECT count(*) FROM pg_trigger WHERE tgenabled='O' AND tgtype=31 AND tgfoid=boundary_oid AND
           ((tgrelid='public.task_waiting_history'::regclass AND tgname='mq20_view_only_task_waiting_history') OR
            (tgrelid='public.task_blocker_history'::regclass AND tgname='mq20_view_only_task_blocker_history'))) <> 2 THEN
      RAISE EXCEPTION 'MQ-20 security boundary or context differs from reviewed Staging baseline';
    END IF;
    SELECT pg_get_functiondef(boundary_oid),jsonb_build_array(proowner,prosecdef,proconfig,proacl)
      INTO boundary_definition,boundary_security FROM pg_proc WHERE oid=boundary_oid;
    IF position('  RAISE EXCEPTION ''MQ-20 task access is view-only''' IN boundary_definition)=0 THEN
      RAISE EXCEPTION 'MQ-20 boundary insertion point missing';
    END IF;
    boundary_definition := replace(boundary_definition,
      '  RAISE EXCEPTION ''MQ-20 task access is view-only''',
      $boundary$  -- Only the private, transaction-bound RPC context can write its own histories.
  IF TG_TABLE_NAME = 'task_waiting_history' THEN
    IF TG_OP = 'INSERT' AND NEW.actor_id IS NOT DISTINCT FROM auth.uid()
       AND hrsys_private.valid_mq20_task_context(NEW.task_id,'EXECUTION','WAIT') THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND NEW.task_id IS NOT DISTINCT FROM OLD.task_id
       AND NEW.resumed_by IS NOT DISTINCT FROM auth.uid()
       AND (to_jsonb(NEW)-ARRAY['resumed_at','resumed_by']) = (to_jsonb(OLD)-ARRAY['resumed_at','resumed_by'])
       AND hrsys_private.valid_mq20_task_context(NEW.task_id,'EXECUTION','RESUME') THEN RETURN NEW; END IF;
  ELSIF TG_TABLE_NAME = 'task_blocker_history' THEN
    IF TG_OP = 'INSERT' AND NEW.actor_id IS NOT DISTINCT FROM auth.uid()
       AND hrsys_private.valid_mq20_task_context(NEW.task_id,'EXECUTION','BLOCK') THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND NEW.task_id IS NOT DISTINCT FROM OLD.task_id
       AND NEW.resolved_by IS NOT DISTINCT FROM auth.uid()
       AND (to_jsonb(NEW)-ARRAY['resolved_at','resolved_by']) = (to_jsonb(OLD)-ARRAY['resolved_at','resolved_by'])
       AND hrsys_private.valid_mq20_task_context(NEW.task_id,'EXECUTION','RESUME') THEN RETURN NEW; END IF;
  END IF;
  RAISE EXCEPTION 'MQ-20 task access is view-only'$boundary$);
    EXECUTE boundary_definition;
    IF boundary_security IS DISTINCT FROM (SELECT jsonb_build_array(proowner,prosecdef,proconfig,proacl) FROM pg_proc WHERE oid=boundary_oid)
       OR md5(replace(replace(pg_get_functiondef(boundary_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> '6eeff07ec9f9d30d63e06c341bc0700f' THEN
      RAISE EXCEPTION 'MQ-20 boundary security metadata changed';
    END IF;
  ELSIF boundary_oid IS NULL OR md5(replace(replace(pg_get_functiondef(boundary_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> '7a2b93f1e12e3d4ed20fa52ccbb0d972' THEN
    RAISE EXCEPTION 'Production MQ-20 boundary differs from reviewed baseline';
  END IF;
  SELECT oid INTO attachment_policy_oid FROM pg_policy
    WHERE polrelid='public.task_attachments'::regclass AND polname='task_attachment_versioned_select'
      AND polpermissive AND polcmd='r' AND polroles=ARRAY['authenticated'::regrole::oid]
      AND md5(pg_get_expr(polqual,polrelid))='0f3a73556bedf222468f3eb3e4fd7eb9';
  IF attachment_policy_oid IS NULL OR to_regprocedure('public.current_user_linked_project_task(uuid)') IS NOT NULL
     OR to_regprocedure('public.can_read_current_task_attachment(uuid)') IS NOT NULL
     OR NOT has_table_privilege('authenticated','public.tasks','SELECT')
     OR has_table_privilege('authenticated','public.projects','SELECT')
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.task_attachments'::regclass AND relrowsecurity)
     OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.task_attachments'::regclass
         AND polname='mq20_only_ines_task_attachments_select' AND NOT polpermissive AND polcmd='r'
         AND polroles=ARRAY['authenticated'::regrole::oid] AND md5(pg_get_expr(polqual,polrelid))='990cca611f144c83965eee120c4603b7') THEN
    RAISE EXCEPTION 'Attachment policy, helper absence, or task grants differ from reviewed baseline';
  END IF;
  IF to_regclass('storage.objects') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid=to_regclass('storage.objects') AND relrowsecurity)
     OR NOT has_table_privilege('authenticated',to_regclass('storage.objects'),'SELECT')
     OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid=to_regclass('storage.objects')
       AND polname='sensitive_task_attachments_read' AND polpermissive AND polcmd='r'
       AND polroles=ARRAY['authenticated'::regrole::oid]
       AND md5(pg_get_expr(polqual,polrelid))='420ada83a0c9d7d86547d72bcd659868') THEN
    RAISE EXCEPTION 'Task attachment Storage SELECT policy or grants differ from reviewed baseline';
  END IF;
  -- Fail closed if the reviewed attachment authorization dependencies drift.
  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('public.can_access_task(uuid,uuid)', CASE WHEN staging_case THEN 'a7bd4e222376bcda23e5c7286e9cd553' ELSE 'cf2adeb248ea95c4f56d88f40e015347' END, false, true),
      ('public.can_view_task(uuid,uuid)', '43222546184444a60845613a959ee84f', staging_case, true),
      ('public.can_assign_tasks_company_wide(uuid)', '85e0f6b1d4296eae51f53df0196883b0', staging_case, true),
      ('public.can_view_task_via_employee_grant(uuid,uuid)', 'ac0d6abc1581f3362c93048a1891f725', staging_case, true),
      ('public.can_marketing_manager_edit_task(uuid,uuid)', '2633ee00e4d64b5dabec039aee9a4697', staging_case, true),
      ('public.is_mq07_design_list(uuid,uuid)', 'bb7a1fd791f19724feefd52de314d184', false, true),
      ('public.is_ines_modani_task(uuid)', 'dd4a7998caad9150ed7aaf941c272e48', staging_case, true),
      ('public.crm_is_own_generated_contact_task(uuid,uuid)', CASE WHEN staging_case THEN 'd83f83b48ba2f5b1c2b16b8bb1628a2a' ELSE 'f50204fee04d0013efa9f5f94308837a' END, false, true),
      ('public.is_mq20_profile(uuid)', '873a1aecadf1d0fec3fceca822adf6b7', false, false),
      ('public.can_view_task_list(uuid,uuid)', '52cd489a693888d4a342133e72e37446', staging_case, true),
      ('public.can_view_task_list_via_employee_grant(uuid,uuid)', '22c923d023fba38c47472e55c84253e5', staging_case, true),
      ('public.is_task_admin(uuid)', '05d613ffe18da1fbf534c04f14640258', staging_case, true),
      ('public.is_marketing_managed_task_list(uuid)', '31d62efb033a10094508eb2d2c9e58bf', staging_case, true),
      ('public.is_marketing_task_manager(uuid)', '6af8123cdf7fde1a692c9bcb9efecbc8', staging_case, true),
      ('public.is_ines_modani_profile(uuid)', '3412eaa6e3f2ffccd8f581ab6be19638', staging_case, true),
      ('public.is_project_portfolio_admin(uuid)', 'a6d51041f83626dbe67822554a6c7d12', staging_case, true)
    ) AS required(signature, fingerprint, anon_execute, authenticated_execute)
    LEFT JOIN pg_proc p ON p.oid=to_regprocedure(required.signature)
    WHERE p.oid IS NULL OR (CASE WHEN required.signature='public.crm_is_own_generated_contact_task(uuid,uuid)' THEN md5(replace(replace(pg_get_functiondef(p.oid), E'\r\n', E'\n'), E'\r', E'\n')) ELSE md5(pg_get_functiondef(p.oid)) END)<>required.fingerprint
       OR p.proowner<>'postgres'::regrole OR NOT p.prosecdef
       OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, pg_temp']::text[]
       OR has_function_privilege('anon',p.oid,'EXECUTE') IS DISTINCT FROM required.anon_execute
       OR has_function_privilege('authenticated',p.oid,'EXECUTE') IS DISTINCT FROM required.authenticated_execute
       OR NOT has_function_privilege('service_role',p.oid,'EXECUTE')
  ) THEN RAISE EXCEPTION 'Attachment dependency fingerprint or security metadata differs from reviewed baseline'; END IF;
  EXECUTE replace(replace($ddl$
    CREATE FUNCTION public.current_user_linked_project_task(p_task_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
    AS $body$
      SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.tasks task JOIN public.projects project
          ON project.id=task.project_id OR (project.deal_id IS NOT NULL AND project.deal_id=task.crm_deal_id)
        WHERE task.id=p_task_id
          AND auth.uid()=ANY(COALESCE(project.assigned_people,ARRAY[]::uuid[]))
          AND public.can_access_task(task.id,auth.uid())
          AND (public.can_view_task(task.id,auth.uid()) OR task.created_by=auth.uid()
            OR public.can_assign_tasks_company_wide(auth.uid())
            OR public.can_view_task_via_employee_grant(task.id,auth.uid())
            OR public.can_marketing_manager_edit_task(task.id,auth.uid())
            OR public.is_mq07_design_list(task.task_list_id,auth.uid()))
      )
    $body$;
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  ALTER FUNCTION public.current_user_linked_project_task(uuid) OWNER TO postgres;
  REVOKE ALL ON FUNCTION public.current_user_linked_project_task(uuid) FROM PUBLIC,anon,authenticated,service_role;
  GRANT EXECUTE ON FUNCTION public.current_user_linked_project_task(uuid) TO authenticated;
  -- One caller-bound decision governs both metadata and binary reads.
  EXECUTE replace(replace($ddl$
    CREATE FUNCTION public.can_read_current_task_attachment(p_attachment_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
    AS $body$
      SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.task_attachments a
        WHERE a.id=p_attachment_id
          AND (NOT public.is_mq20_profile(auth.uid()) OR public.is_ines_modani_task(a.task_id)
            OR public.crm_is_own_generated_contact_task(a.task_id,auth.uid()))
          AND (public.can_manage_task_attachments(a.task_id,auth.uid())
            OR (a.is_archived=false AND public.crm_is_own_generated_contact_task(a.task_id,auth.uid())
              AND public.can_access_task(a.task_id,auth.uid()))
            OR (a.is_archived=false AND a.visible_to_project_assignee=true
              AND public.current_user_linked_project_task(a.task_id)))
      )
    $body$;
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  ALTER FUNCTION public.can_read_current_task_attachment(uuid) OWNER TO postgres;
  REVOKE ALL ON FUNCTION public.can_read_current_task_attachment(uuid) FROM PUBLIC,anon,authenticated,service_role;
  GRANT EXECUTE ON FUNCTION public.can_read_current_task_attachment(uuid) TO authenticated;
  DROP POLICY task_attachment_versioned_select ON public.task_attachments;
  CREATE POLICY task_attachment_versioned_select ON public.task_attachments FOR SELECT TO authenticated
    USING (public.can_read_current_task_attachment(id));
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.current_user_linked_project_task(uuid)'::regprocedure
       AND proowner='postgres'::regrole AND prosecdef AND 'search_path=public, pg_temp'=ANY(proconfig))
     OR has_function_privilege('anon','public.current_user_linked_project_task(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.current_user_linked_project_task(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.current_user_linked_project_task(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Attachment authorization helper security postcheck failed';
  END IF;
  IF attachment_reader_oid IS NULL OR md5(replace(replace(pg_get_functiondef(attachment_reader_oid), E'\r\n', E'\n'), E'\r', E'\n')) <>
       (CASE WHEN staging_case THEN 'd0bbd53cff17e3914bf912b7e590b565' ELSE '93c1bc1a52517b65c16dac9ee4c29b55' END)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=attachment_reader_oid AND proowner='postgres'::regrole
       AND prosecdef AND 'search_path=public, pg_temp'=ANY(proconfig))
     OR has_function_privilege('anon',attachment_reader_oid,'EXECUTE')
     OR NOT has_function_privilege('authenticated',attachment_reader_oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',attachment_reader_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Attachment Storage reader differs from reviewed baseline';
  END IF;
  IF attachment_manager_oid IS NULL OR md5(replace(replace(pg_get_functiondef(attachment_manager_oid), E'\r\n', E'\n'), E'\r', E'\n')) <>
       (CASE WHEN staging_case THEN '6f6e252dcf1908ef50c33e7c1048a50f' ELSE 'ebab23adaeaa8f01ba3b3142868c2f56' END)
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=attachment_manager_oid AND proowner='postgres'::regrole
       AND prosecdef AND 'search_path=public, pg_temp'=ANY(proconfig))
     OR has_function_privilege('anon',attachment_manager_oid,'EXECUTE')
     OR NOT has_function_privilege('authenticated',attachment_manager_oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',attachment_manager_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Attachment management helper differs from reviewed baseline';
  END IF;
  SELECT pg_get_functiondef(attachment_manager_oid),jsonb_build_array(proowner,prosecdef,proconfig,proacl)
    INTO attachment_manager_definition,attachment_manager_security FROM pg_proc WHERE oid=attachment_manager_oid;
  IF position('SELECT p_user_id IS NOT NULL' IN attachment_manager_definition)=0 THEN
    RAISE EXCEPTION 'Attachment management caller check not found';
  END IF;
  attachment_manager_definition := replace(attachment_manager_definition,'SELECT p_user_id IS NOT NULL',
    'SELECT NOT (auth.uid() IS NULL AND current_setting(''role'',true) = ''authenticated'') AND p_user_id IS NOT NULL');
  EXECUTE attachment_manager_definition;
  IF attachment_manager_security IS DISTINCT FROM (SELECT jsonb_build_array(proowner,prosecdef,proconfig,proacl) FROM pg_proc WHERE oid=attachment_manager_oid)
     OR md5(replace(replace(pg_get_functiondef(attachment_manager_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> (CASE WHEN staging_case THEN '1a9d5dd09b536d631f8fe10bf18353a6' ELSE '5c9e6da7fcfa4160da8f0331e7f460af' END) THEN
    RAISE EXCEPTION 'Attachment management security metadata changed';
  END IF;
  SELECT jsonb_build_array(proowner,prosecdef,proconfig,proacl) INTO attachment_reader_security FROM pg_proc WHERE oid=attachment_reader_oid;
  EXECUTE replace(replace($ddl$
  CREATE OR REPLACE FUNCTION public.can_read_task_attachment_file(p_object_name text,p_user_id uuid DEFAULT auth.uid())
  RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
  AS $body$
  BEGIN
    IF p_user_id IS NULL OR (auth.uid() IS NOT NULL AND p_user_id <> auth.uid()) THEN RETURN false; END IF;
    IF auth.uid() IS NULL AND current_setting('role',true) = 'authenticated' THEN RETURN false; END IF;
    IF auth.uid() IS NULL THEN
      RETURN EXISTS (SELECT 1 FROM public.task_attachments a JOIN public.tasks t ON t.id=a.task_id
        LEFT JOIN public.projects p ON p.id=t.project_id
        WHERE a.file_url='storage://task-attachments/'||p_object_name
          AND (public.can_access_task(t.id,p_user_id) OR (p.id IS NOT NULL AND p_user_id=ANY(COALESCE(p.assigned_people,ARRAY[]::uuid[])))));
    END IF;
    RETURN EXISTS (SELECT 1 FROM public.task_attachments a WHERE a.file_url='storage://task-attachments/'||p_object_name
      AND public.can_read_current_task_attachment(a.id));
  END;
  $body$;
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  IF attachment_reader_security IS DISTINCT FROM (SELECT jsonb_build_array(proowner,prosecdef,proconfig,proacl) FROM pg_proc WHERE oid=attachment_reader_oid)
     OR md5(replace(replace(pg_get_functiondef(attachment_reader_oid), E'\r\n', E'\n'), E'\r', E'\n')) <> '12f596bf0d16fc7eb9c65317f0806afb'
     OR md5(replace(replace(pg_get_functiondef('public.current_user_linked_project_task(uuid)'::regprocedure), E'\r\n', E'\n'), E'\r', E'\n')) <> 'f9e6755808ef9bff2dc4d7b61ac1de98'
     OR md5(replace(replace(pg_get_functiondef('public.can_read_current_task_attachment(uuid)'::regprocedure), E'\r\n', E'\n'), E'\r', E'\n')) <> 'f51ee9b08ad198ae5b576c6de25fea1b'
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_read_current_task_attachment(uuid)'::regprocedure
        AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp']::text[])
     OR has_function_privilege('anon','public.can_read_current_task_attachment(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.can_read_current_task_attachment(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.can_read_current_task_attachment(uuid)','EXECUTE')
     OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.task_attachments'::regclass
       AND polname='task_attachment_versioned_select' AND md5(pg_get_expr(polqual,polrelid))='cfad84c5a74f3f94cf343ea3ad6b3c12')
     OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.task_attachments'::regclass
       AND polname='mq20_only_ines_task_attachments_select' AND NOT polpermissive AND md5(pg_get_expr(polqual,polrelid))='990cca611f144c83965eee120c4603b7')
     OR has_table_privilege('authenticated','public.projects','SELECT') THEN
    RAISE EXCEPTION 'Attachment Storage reader security metadata changed (reader %, policy %, helper %)'
      ,md5(replace(replace(pg_get_functiondef(attachment_reader_oid), E'\r\n', E'\n'), E'\r', E'\n')),
       (SELECT md5(pg_get_expr(polqual,polrelid)) FROM pg_policy WHERE polrelid='public.task_attachments'::regclass AND polname='task_attachment_versioned_select'),
       md5(replace(replace(pg_get_functiondef('public.can_read_current_task_attachment(uuid)'::regprocedure), E'\r\n', E'\n'), E'\r', E'\n'));
  END IF;
END;
$migration$;
COMMIT;
