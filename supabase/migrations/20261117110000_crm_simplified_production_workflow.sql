-- Production baseline only: atomic generic bridge and simplified workflow. Verify release gates before execution.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $production_baseline$ BEGIN
 IF current_user <> 'postgres' OR current_database() <> 'postgres' OR current_setting('server_version_num')::int NOT BETWEEN 170000 AND 179999 THEN RAISE EXCEPTION 'Unexpected Production fixture role/version/database'; END IF;
 IF to_regprocedure('public.ensure_crm_generated_task(uuid,text)') IS NOT NULL OR to_regprocedure('public.protect_crm_generated_task_identity()') IS NOT NULL THEN RAISE EXCEPTION 'Unexpected generated-task foundation'; END IF;
 IF to_regprocedure('public.crm_current_user_can_read_project_shared_attachment(uuid)') IS NOT NULL OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='crm_deal_attachments' AND policyname='crm_project_shared_attachments_select' AND permissive='PERMISSIVE' AND cmd='SELECT' AND roles=ARRAY['authenticated']::name[] AND md5(qual)='d365bd9a306d4684348c68de08c83cc3' AND with_check IS NULL) THEN RAISE EXCEPTION 'Project-shared policy baseline differs'; END IF;
 IF md5(replace(pg_get_functiondef('public.enforce_task_completion_approval()'::regprocedure),E'\r\n',E'\n')) <> '2ec95692894b2de4657f316a84eb09e1'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.enforce_task_completion_approval()'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.enforce_private_task_list_ownership()'::regprocedure),E'\r\n',E'\n')) <> '6eb8a020a1d6f6a64ffa0ab8462b94b1'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.enforce_private_task_list_ownership()'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.can_read_crm_deal_file(text,uuid)'::regprocedure),E'\r\n',E'\n')) <> 'ffe59b1b1f8671325a009549a2755691'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.can_read_crm_deal_file(text,uuid)'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.can_access_task(uuid,uuid)'::regprocedure),E'\r\n',E'\n')) <> 'cf2adeb248ea95c4f56d88f40e015347'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.can_access_task(uuid,uuid)'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.can_manage_task(uuid,uuid)'::regprocedure),E'\r\n',E'\n')) <> '86544056ca930279dffb1835a9480e62'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.can_manage_task(uuid,uuid)'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.can_manage_task_attachments(uuid,uuid)'::regprocedure),E'\r\n',E'\n')) <> '5c9e6da7fcfa4160da8f0331e7f460af'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.can_manage_task_attachments(uuid,uuid)'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.enforce_crm_design_task_completion()'::regprocedure),E'\r\n',E'\n')) <> '4f456adceb022e91852b41c6f7cec2ea'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.enforce_crm_design_task_completion()'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.enforce_deal_workflow_transition()'::regprocedure),E'\r\n',E'\n')) <> 'ff9e0e0ef50257b4b42175564bba8a25'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.enforce_deal_workflow_transition()'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS FALSE AND p.proconfig IS NULL AND has_function_privilege('anon',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.change_crm_deal_stage(uuid,text)'::regprocedure),E'\r\n',E'\n')) <> 'ecf85ecf33decad1b75be756c340d062'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.change_crm_deal_stage(uuid,text)'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.can_execute_task(uuid,uuid)'::regprocedure),E'\r\n',E'\n')) <> 'dd37435aae7d74c801ed3b65b3d85ff4'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.can_execute_task(uuid,uuid)'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('service_role',p.oid,'EXECUTE'))
 OR md5(replace(pg_get_functiondef('public.create_project_from_won_deal_v2(uuid,jsonb)'::regprocedure),E'\r\n',E'\n')) <> '33e160d75988697ff3ca9e37a8bb0fb6'
 OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.create_project_from_won_deal_v2(uuid,jsonb)'::regprocedure AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef IS TRUE AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[] AND has_function_privilege('anon',p.oid,'EXECUTE') IS FALSE AND has_function_privilege('authenticated',p.oid,'EXECUTE') IS TRUE AND has_function_privilege('service_role',p.oid,'EXECUTE')) THEN RAISE EXCEPTION 'Production generic dependency fingerprint mismatch'; END IF;
END $production_baseline$;
CREATE OR REPLACE FUNCTION public.enforce_task_completion_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NEW.crm_workflow_kind IN ('CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN') THEN RETURN NEW; END IF;
    IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
        IF public.is_task_department_manager(NEW.department, auth.uid()) THEN
            NEW.completion_approved_by := auth.uid();
            NEW.completion_approved_at := now();
        ELSE
            NEW.status := 'Pending Approval';
            NEW.completion_requested_by := auth.uid();
            NEW.completion_requested_at := now();
            NEW.completion_approved_by := NULL;
            NEW.completion_approved_at := NULL;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.enforce_private_task_list_ownership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.task_list_id IS NULL THEN RETURN NEW; END IF;
  IF NOT COALESCE(public.can_add_task_to_list(NEW.task_list_id, auth.uid()), false) THEN
    RAISE EXCEPTION 'You cannot add tasks to this task list' USING ERRCODE = '42501';
  END IF;
  NEW.visibility := 'private'; NEW.visible_to := '{}'; NEW.supervisor_id := NULL;
  RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.can_read_crm_deal_file(p_object_name text, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() AND current_setting('role',true) IS DISTINCT FROM 'service_role' THEN
    RETURN false;
  END IF;
  IF public.can_access_crm(p_user_id) THEN RETURN true; END IF;
  RETURN EXISTS (
    SELECT 1
      FROM public.crm_deal_attachments attachment
      JOIN public.projects project ON project.deal_id = attachment.deal_id
     WHERE attachment.file_url = 'storage://crm-deal-files/' || p_object_name
       AND attachment.is_archived = false
       AND attachment.visible_to_project_assignee = true
       AND p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::uuid[]))
  );
END;
$function$;
CREATE OR REPLACE FUNCTION public.can_access_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.tasks task
    WHERE task.id = p_task_id
      AND p_user_id IS NOT NULL
      AND (auth.uid() IS NULL OR p_user_id = auth.uid())
      AND (
        auth.uid() IS NULL
        OR NOT public.is_mq20_profile(auth.uid())
        OR public.is_ines_modani_task(task.id)
        OR public.crm_is_own_generated_contact_task(task.id, auth.uid())
      )
      AND (
        task.created_by = p_user_id
        OR task.assignee_id = p_user_id
        OR task.supervisor_id = p_user_id
        OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
        OR p_user_id = ANY(COALESCE(task.visible_to, '{}'::uuid[]))
        OR public.can_assign_tasks_company_wide(p_user_id)
        OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
        OR public.can_view_task_via_employee_grant(p_task_id, p_user_id)
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list(task.task_list_id, p_user_id))
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list_via_employee_grant(task.task_list_id, p_user_id))
      )
  );
$function$;
CREATE OR REPLACE FUNCTION public.can_manage_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_user_id IS NOT NULL
    AND (auth.uid() IS NULL OR p_user_id = auth.uid())
    AND (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
    AND EXISTS (
      SELECT 1
      FROM public.tasks task
      LEFT JOIN public.task_lists list ON list.id = task.task_list_id
      WHERE task.id = p_task_id
        AND (
          task.created_by = p_user_id
          OR task.supervisor_id = p_user_id
          OR public.can_assign_tasks_company_wide(p_user_id)
          OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
          OR p_user_id = ANY(COALESCE(list.can_delete_users, '{}'::uuid[]))
        )
    );
$function$;
CREATE OR REPLACE FUNCTION public.can_manage_task_attachments(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT NOT (auth.uid() IS NULL AND current_setting('role',true) = 'authenticated') AND p_user_id IS NOT NULL
    AND (auth.uid() IS NULL OR p_user_id = auth.uid())
    AND (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
    AND EXISTS (
      SELECT 1
      FROM public.tasks task
      LEFT JOIN public.projects project ON project.id = task.project_id
      WHERE task.id = p_task_id
        AND (
          task.created_by = p_user_id
          OR task.assignee_id = p_user_id
          OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
          OR task.supervisor_id = p_user_id
          OR project.created_by = p_user_id
          OR project.project_manager_id = p_user_id
          OR public.is_project_portfolio_admin(p_user_id)
        )
    );
$function$;
CREATE OR REPLACE FUNCTION public.enforce_crm_design_task_completion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'
     AND LOWER(BTRIM(NEW.status)) = 'completed' AND LOWER(BTRIM(OLD.status)) IS DISTINCT FROM 'completed' THEN
    IF auth.uid() IS NULL OR NOT COALESCE(public.can_access_task(OLD.id, auth.uid()), false)
       OR NOT (auth.uid() = OLD.assignee_id OR auth.uid() = ANY(COALESCE(OLD.assignee_ids, '{}'::uuid[]))
         OR public.can_manage_task(OLD.id, auth.uid())) THEN
      RAISE EXCEPTION 'Design task access denied' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(cardinality(NEW.submission_links), 0) = 0 OR EXISTS (
      SELECT 1 FROM unnest(NEW.submission_links) link WHERE NOT EXISTS (
        SELECT 1 FROM public.task_attachments attachment WHERE attachment.task_id = NEW.id
          AND attachment.file_url = link AND attachment.is_archived = false
          AND (attachment.file_type = 'application/pdf' OR attachment.file_type LIKE 'image/%')
      )) THEN RAISE EXCEPTION 'Upload completed Design PDFs or images first' USING ERRCODE = '23514'; END IF;
    INSERT INTO public.crm_deal_activity(deal_id, action, note, actor_id)
      VALUES (NEW.crm_deal_id, 'DESIGN_COMPLETED', NEW.id::text, auth.uid());
  END IF;
  RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.stage = 'LOST' AND NULLIF(BTRIM(COALESCE(NEW.lost_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A lost reason is required' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.change_crm_deal_stage(p_deal_id uuid, p_new_stage text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  $function$;
CREATE OR REPLACE FUNCTION public.can_execute_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_user_id IS NOT NULL
    AND (auth.uid() IS NULL OR p_user_id = auth.uid())
    AND (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
    AND EXISTS (
      SELECT 1
      FROM public.tasks task
      JOIN public.profiles profile ON profile.id = p_user_id
      WHERE task.id = p_task_id
        AND profile.is_active IS DISTINCT FROM false
        AND (
          profile.id IN (task.created_by, task.assignee_id, task.supervisor_id)
          OR profile.id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
          OR UPPER(COALESCE(profile.role, '')) IN ('ADMIN', 'MANAGER', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'CEO', 'GM', 'GENERAL MANAGER')
          OR UPPER(COALESCE(profile.job_title, '')) IN ('CEO', 'GM', 'GENERAL MANAGER')
        )
    );
$function$;
CREATE OR REPLACE FUNCTION public.create_project_from_won_deal_v2(p_deal_id uuid, p_order jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_project_id uuid;
    v_assigned uuid[];
    v_event_date date;
    v_event_end_date date;
    v_event_start_time time;
    v_installation_time timestamp without time zone;
    v_uninstallation_time timestamp without time zone;
    v_equipment jsonb;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deal not found'; END IF;
    IF auth.uid() IS NULL OR NOT COALESCE(public.can_access_crm(auth.uid()), false)
       OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_active IS DISTINCT FROM false) THEN
        RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
    END IF;
    IF v_deal.stage = 'LOST' THEN RAISE EXCEPTION 'Reopen the deal before opening a project'; END IF;
    IF v_deal.proposal_sent_at IS NULL
       OR (v_deal.stage NOT IN ('PITCH', 'PROPOSAL', 'NEGOTIATION')
           AND NOT (v_deal.stage = 'WON' AND EXISTS (
               SELECT 1 FROM public.projects WHERE deal_id = p_deal_id
           ))) THEN
        RAISE EXCEPTION 'Submit the Presentation before opening a project' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id = p_deal_id AND category = 'QUOTATION' AND is_archived = false) THEN
        RAISE EXCEPTION 'Upload a quote document first' USING ERRCODE = '23514';
    END IF;
    IF (v_deal.approval_type = 'QUOTE_PROPOSAL' OR v_deal.design_task_id IS NOT NULL) AND (
        NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id = p_deal_id AND category = 'PROPOSAL' AND is_archived = false)
        OR NOT EXISTS (SELECT 1 FROM public.tasks WHERE id = v_deal.design_task_id AND LOWER(status) = 'completed'
            AND COALESCE(cardinality(submission_links), 0) > 0)
    ) THEN RAISE EXCEPTION 'Complete the proposal Design and its required deliverables first' USING ERRCODE = '23514'; END IF;
    IF NOT COALESCE(public.can_view_business_financials(auth.uid()), false)
       AND (p_order ? 'project_amount' OR p_order ? 'paid_amount') THEN
        RAISE EXCEPTION 'Financial access denied' USING ERRCODE = '42501';
    END IF;
    IF auth.uid() IS DISTINCT FROM v_deal.created_by AND auth.uid() IS DISTINCT FROM v_deal.assigned_to
       AND NOT public.is_crm_approval_admin(auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND UPPER(COALESCE(p.role, '')) = 'MANAGER') THEN
        RAISE EXCEPTION 'Only the deal team or management can open this project';
    END IF;

    SELECT COALESCE(array_agg(value::uuid), '{}') INTO v_assigned
    FROM jsonb_array_elements_text(COALESCE(p_order->'assigned_people', '[]'::jsonb)) value;

    IF NULLIF(BTRIM(COALESCE(p_order->>'event_date', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->>'event_start_time', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->'client'->>'name', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->>'installation_type', '')), '') IS NULL THEN
        RAISE EXCEPTION 'Event date, starting time, client name, and installation type are required';
    END IF;

    v_event_date := (p_order->>'event_date')::date;
    v_event_end_date := COALESCE(NULLIF(p_order->>'event_end_date', '')::date, v_event_date);
    v_event_start_time := (p_order->>'event_start_time')::time;
    IF v_event_end_date < v_event_date THEN
        RAISE EXCEPTION 'Event End Date cannot be before the Event Date';
    END IF;
    v_installation_time := COALESCE(
        NULLIF(p_order->>'installation_time', '')::timestamp,
        (v_event_date + v_event_start_time) - INTERVAL '2 days'
    );
    v_uninstallation_time := COALESCE(
        NULLIF(p_order->>'uninstallation_time', '')::timestamp,
        (v_event_end_date + v_event_start_time) + INTERVAL '2 days'
    );

    IF COALESCE(array_length(v_assigned, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one employee';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(v_assigned) assignee_id
        LEFT JOIN public.profiles profile ON profile.id = assignee_id
        WHERE profile.id IS NULL OR profile.is_active IS FALSE
    ) THEN
        RAISE EXCEPTION 'Projects can only be assigned to active employees';
    END IF;

    IF p_order ? 'equipment' AND jsonb_typeof(p_order->'equipment') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Equipment must be an array';
    END IF;
    v_equipment := CASE
        WHEN jsonb_typeof(p_order->'equipment') = 'array' THEN p_order->'equipment'
        ELSE '[]'::jsonb
    END;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_equipment) equipment_item
        WHERE NULLIF(BTRIM(COALESCE(equipment_item->>'item', '')), '') IS NULL
           OR NULLIF(BTRIM(COALESCE(equipment_item->>'quantity', '')), '') IS NULL
    ) THEN
        RAISE EXCEPTION 'Every added equipment item needs an item name and quantity';
    END IF;

    SELECT id INTO v_project_id FROM public.projects WHERE deal_id = p_deal_id ORDER BY created_at LIMIT 1 FOR UPDATE;
    IF v_project_id IS NULL THEN
        INSERT INTO public.projects(
            project_name, project_type, description, assigned_people, project_tags,
            deal_id, client_id, event_date, start_date, end_date, event_location, project_amount,
            paid_amount, project_status, source, order_employee_id, event_start_time,
            installation_time, uninstallation_time, client_snapshot, event_location_text,
            installation_type, equipment
        ) VALUES (
            v_deal.title, 'Client', NULLIF(p_order->>'notes', ''), v_assigned, ARRAY['Won Deal']::text[],
            v_deal.id, v_deal.client_id, v_event_date, v_event_date, v_event_end_date,
            NULLIF(p_order->>'location_url', ''), COALESCE(NULLIF(p_order->>'project_amount', '')::numeric, v_deal.amount, 0),
            COALESCE(NULLIF(p_order->>'paid_amount', '')::numeric, 0), 'Not Confirmed', 'WON_DEAL',
            auth.uid(), v_event_start_time, v_installation_time, v_uninstallation_time,
            p_order->'client', NULLIF(p_order->>'location_text', ''),
            p_order->>'installation_type', v_equipment
        ) RETURNING id INTO v_project_id;
    ELSE
        UPDATE public.projects SET
            description = NULLIF(p_order->>'notes', ''), assigned_people = v_assigned,
            event_date = v_event_date, start_date = v_event_date, end_date = v_event_end_date,
            event_location = NULLIF(p_order->>'location_url', ''),
            project_amount = CASE WHEN public.can_view_business_financials(auth.uid())
                THEN COALESCE(NULLIF(p_order->>'project_amount', '')::numeric, v_deal.amount, 0) ELSE project_amount END,
            paid_amount = CASE WHEN public.can_view_business_financials(auth.uid())
                THEN COALESCE(NULLIF(p_order->>'paid_amount', '')::numeric, 0) ELSE paid_amount END,
            order_employee_id = auth.uid(), event_start_time = v_event_start_time,
            installation_time = v_installation_time, uninstallation_time = v_uninstallation_time,
            client_snapshot = p_order->'client', event_location_text = NULLIF(p_order->>'location_text', ''),
            installation_type = p_order->>'installation_type', equipment = v_equipment
        WHERE id = v_project_id;
    END IF;

    UPDATE public.crm_deals SET stage = 'WON' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (p_deal_id, 'PROJECT_CREATED', v_deal.stage, 'WON', NULLIF(p_order->>'notes', ''), auth.uid());
    RETURN v_project_id;
END;
$function$;
CREATE OR REPLACE FUNCTION public.ensure_crm_generated_task(p_deal_id uuid, p_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_deal public.crm_deals%ROWTYPE;
  v_task_id uuid;
  v_assignee uuid;
  v_list uuid;
  v_department text;
  v_supervisor uuid;
  v_title text;
  v_list_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT COALESCE(public.can_access_crm(auth.uid()), false)
     OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
  SELECT task_id INTO v_task_id FROM public.crm_generated_tasks WHERE deal_id = p_deal_id AND kind = p_kind;
  IF FOUND THEN RETURN v_task_id; END IF;
  IF p_kind = 'CONTACT_DISCUSSION' THEN
    v_assignee := auth.uid();
    SELECT department.name, department.head_id INTO v_department, v_supervisor
    FROM public.profiles profile LEFT JOIN public.departments department ON department.id = profile.department_id
    WHERE profile.id = auth.uid();
    SELECT COALESCE(NULLIF(BTRIM(client.name), ''), v_deal.title) || ' discussion'
      INTO v_title FROM public.crm_clients client WHERE client.id = v_deal.client_id;
    v_title := COALESCE(v_title, v_deal.title || ' discussion');
  ELSIF p_kind = 'QUOTE_PROPOSAL_DESIGN' THEN
    -- Do not guess which historic task to adopt if the deal pointer is missing.
    IF EXISTS (SELECT 1 FROM public.tasks WHERE crm_deal_id = p_deal_id AND crm_workflow_kind = p_kind) THEN
      RAISE EXCEPTION 'Existing Design task needs an explicit deal link repair' USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO v_list_count FROM public.profiles WHERE emp_index = 8 AND is_active IS DISTINCT FROM false;
    IF v_list_count <> 1 THEN RAISE EXCEPTION 'Configure exactly one active MQ-08 employee' USING ERRCODE = '23514'; END IF;
    SELECT id INTO v_assignee FROM public.profiles WHERE emp_index = 8 AND is_active IS DISTINCT FROM false;
    IF v_assignee IS NULL THEN RAISE EXCEPTION 'Employee MQ-08 must be configured' USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_list_count FROM public.task_lists WHERE COALESCE(name, '') ~* '(design|تصميم)';
    IF v_list_count <> 1 THEN RAISE EXCEPTION 'Configure exactly one Design task list' USING ERRCODE = '23514'; END IF;
    SELECT list.id, department.name INTO v_list, v_department FROM public.task_lists list
      JOIN public.departments department ON department.id = list.department_id
      WHERE COALESCE(list.name, '') ~* '(design|تصميم)';
    IF v_list IS NULL OR NOT COALESCE(public.can_add_task_to_list(v_list, auth.uid()), false) THEN
      RAISE EXCEPTION 'Design task-list access denied' USING ERRCODE = '42501';
    END IF;
    v_title := 'Design proposal: ' || v_deal.title;
  ELSE RAISE EXCEPTION 'Invalid CRM task kind' USING ERRCODE = '22023';
  END IF;
  v_task_id := gen_random_uuid();
  INSERT INTO public.crm_generated_tasks(deal_id, kind, task_id) VALUES (p_deal_id, p_kind, v_task_id);
  -- created_at is deliberately omitted: the task table supplies its server default.
  INSERT INTO public.tasks(id, title, description, assignee_id, assignee_ids, created_by,
    supervisor_id, department, task_list_id, visibility, due_date, status, priority,
    category, sub_type, content_type, crm_deal_id, crm_workflow_kind)
  VALUES (v_task_id, v_title, v_deal.technical_description, v_assignee, ARRAY[v_assignee], auth.uid(),
    v_supervisor, v_department, v_list, 'private',
    CASE WHEN p_kind = 'CONTACT_DISCUSSION' THEN (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Riyadh')::date ELSE NULL END,
    'todo', 'medium', 'CRM', CASE WHEN p_kind = 'QUOTE_PROPOSAL_DESIGN' THEN 'Designing Task' ELSE NULL END,
    CASE WHEN p_kind = 'QUOTE_PROPOSAL_DESIGN' THEN 'Proposal' ELSE NULL END, p_deal_id, p_kind);
  INSERT INTO public.crm_deal_activity(deal_id, action, note, actor_id)
    VALUES (p_deal_id, 'TASK_CREATED', p_kind || ':' || v_task_id::text, auth.uid());
  -- Existing task triggers continue recording activity and assignment notifications.
  RETURN v_task_id;
END;
$function$;
CREATE OR REPLACE FUNCTION public.protect_crm_generated_task_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    -- Preserve the existing privileged deal-deletion path: its FK may detach
    -- surviving tasks, but clients cannot detach a task from an existing deal.
    IF NEW.crm_deal_id IS NULL AND OLD.crm_deal_id IS NOT NULL
       AND NEW.crm_workflow_kind IS NOT DISTINCT FROM OLD.crm_workflow_kind
       AND NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id = OLD.crm_deal_id) THEN
      RETURN NEW;
    END IF;
    IF NEW.crm_deal_id IS DISTINCT FROM OLD.crm_deal_id
       OR NEW.crm_workflow_kind IS DISTINCT FROM OLD.crm_workflow_kind THEN
      RAISE EXCEPTION 'CRM task identity cannot be changed' USING ERRCODE = '42501';
    END IF;
    IF NEW.crm_workflow_kind IN ('CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN')
       AND NEW.status IS DISTINCT FROM OLD.status
       AND LOWER(BTRIM(NEW.status)) IN ('pending approval', 'approved', 'rejected') THEN
      RAISE EXCEPTION 'CRM task approval states are retired' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.crm_deal_id IS NOT NULL OR NEW.crm_workflow_kind IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.crm_generated_tasks
      WHERE task_id = NEW.id AND deal_id = NEW.crm_deal_id AND kind = NEW.crm_workflow_kind) THEN
      RAISE EXCEPTION 'CRM tasks must be generated by the CRM workflow' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
ALTER FUNCTION public.ensure_crm_generated_task(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.ensure_crm_generated_task(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.ensure_crm_generated_task(uuid,text) TO service_role;
ALTER FUNCTION public.protect_crm_generated_task_identity() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.protect_crm_generated_task_identity() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.protect_crm_generated_task_identity() TO service_role;
CREATE TRIGGER protect_crm_generated_task_identity BEFORE INSERT OR UPDATE ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.protect_crm_generated_task_identity();
CREATE FUNCTION public.crm_current_user_can_read_project_shared_attachment(p_attachment uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp' AS $body$
 SELECT auth.uid() IS NOT NULL AND EXISTS (
   SELECT 1 FROM public.crm_deal_attachments attachment JOIN public.projects project ON project.deal_id=attachment.deal_id
   WHERE attachment.id=p_attachment AND attachment.is_archived=false AND attachment.visible_to_project_assignee=true
     AND auth.uid()=ANY(COALESCE(project.assigned_people,ARRAY[]::uuid[]))
 )
$body$;
ALTER FUNCTION public.crm_current_user_can_read_project_shared_attachment(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.crm_current_user_can_read_project_shared_attachment(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.crm_current_user_can_read_project_shared_attachment(uuid) TO authenticated;
ALTER POLICY crm_project_shared_attachments_select ON public.crm_deal_attachments USING (public.crm_current_user_can_read_project_shared_attachment(id));
-- Shared simplified-workflow section following the Production compatibility bridge.
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
DECLARE item record;
BEGIN
  IF current_user <> 'postgres' OR current_setting('server_version_num')::int NOT BETWEEN 170000 AND 179999 THEN
    RAISE EXCEPTION 'Unexpected migration role or PostgreSQL version';
  END IF;
  FOR item IN SELECT * FROM (VALUES
    ('public.ensure_crm_generated_task(uuid,text)','f4cf0fe7a527b44e5f4f51ca3b1b17bd'),
    ('public.protect_crm_generated_task_identity()','f87b9f595740451bae82009de5243555'),
    ('public.enforce_task_completion_approval()','95bf4cbd39d3f0d3fca597bde8ed2a7f'),
    ('public.enforce_marketing_design_review()','5de3c67d0dfecfd1d0cef8e338cf482d'),
    ('public.enforce_private_task_list_ownership()','2aaa8c5edb6569dc16b5eaf76780b058'),
    ('public.can_read_crm_deal_file(text,uuid)','59a03bfe102fa169718a67d5d9072b76'),
    ('public.list_crm_deal_attachments_secure(uuid)','9727df25ed36adb01d231c1f0da33f0c'),
    ('public.can_access_task(uuid,uuid)','a7bd4e222376bcda23e5c7286e9cd553'),
    ('public.can_view_task(uuid,uuid)','efe4475c86c7b975e2e2d66dae2cfde1'),
    ('public.can_manage_task(uuid,uuid)','fc68835f04169ad89d1f052dd0984ee2'),
    ('public.can_manage_task_attachments(uuid,uuid)','1a9d5dd09b536d631f8fe10bf18353a6'),
    ('public.change_task_status(uuid,text)','7bbec9375587105ee0be9350a42e4b58'),
    ('public.can_delete_task(uuid,uuid)','d533732c5a60263f82f2e593e15e37e0'),
    ('public.can_execute_task(uuid,uuid)','6f72cf446da10b7f78cf49849a98f440'),
    ('public.delete_task_secure(uuid)','6e970986266bf96e8067521109ec3821'),
    ('public.task_belongs_to_employee(uuid,uuid)','4db3b76077aaebc28fc71a95625455eb'),
    ('public.enforce_crm_design_task_completion()','ba4ad683421f6cbee33d11be636cfd5f'),
    ('public.sync_crm_design_task_status()','d04129cd545a6410257e28de9fe2c1de'),
    ('public.enforce_deal_workflow_transition()','d9b91256d5a5bd9c4f9494e64131598b'),
    ('public.change_crm_deal_stage(uuid,text)','a8264b38b7d76ee225803775fa6e4d32')
  ) x(signature,fingerprint) LOOP
    IF to_regprocedure(item.signature) IS NULL OR
       md5(replace(pg_get_functiondef(to_regprocedure(item.signature)),E'\r\n',E'\n')) <> item.fingerprint OR
       NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(item.signature)
         AND p.proowner='postgres'::regrole AND p.proconfig=ARRAY['search_path=public, pg_temp']
         AND p.prosecdef=(item.signature <> 'public.enforce_deal_workflow_transition()')) THEN
      RAISE EXCEPTION 'Baseline fingerprint mismatch: %',item.signature;
    END IF;
  END LOOP;
  IF to_regprocedure('public.start_crm_quote_proposal(uuid)') IS NOT NULL
     OR to_regclass('hrsys_private.crm_quote_proposal_context') IS NOT NULL
     OR to_regprocedure('hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)') IS NOT NULL
     OR to_regprocedure('hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[])') IS NOT NULL
     OR to_regprocedure('hrsys_private.can_read_quote_proposal_source(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Quote & Proposal RPC already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.tasks'::regclass AND polname='tasks_select_own_created'
    AND polcmd='r' AND polpermissive AND md5(pg_get_expr(polqual,polrelid))='987767fc803474751ce44a4235a12922') THEN
    RAISE EXCEPTION 'Task creator read policy differs from baseline';
  END IF;
  IF has_function_privilege('anon','public.change_crm_deal_stage(uuid,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.change_crm_deal_stage(uuid,text)','EXECUTE')
     OR has_function_privilege('anon','public.ensure_crm_generated_task(uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.ensure_crm_generated_task(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Workflow execution grants differ';
  END IF;
  IF to_regprocedure('public.enforce_mq20_task_service_boundaries()') IS NULL OR
    md5(replace(pg_get_functiondef('public.enforce_mq20_task_service_boundaries()'::regprocedure),E'\r\n',E'\n'))
      NOT IN ('6eeff07ec9f9d30d63e06c341bc0700f','7a2b93f1e12e3d4ed20fa52ccbb0d972') OR
    NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.enforce_mq20_task_service_boundaries()'::regprocedure
      AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=public, pg_temp']) THEN
    RAISE EXCEPTION 'MQ-20 service boundary differs from reviewed baseline';
  END IF;
  IF md5(replace(pg_get_functiondef('public.start_deal_approval(uuid,uuid,uuid,uuid)'::regprocedure),E'\r\n',E'\n')) <> 'dcb3e4a763f0183be2bc56915732c3bd'
    OR md5(replace(pg_get_functiondef('public.start_crm_presentation_approval(uuid,text)'::regprocedure),E'\r\n',E'\n')) <> 'a54ca3e7069f7cab535d541f9e991e2c'
    OR md5(replace(pg_get_functiondef('public.decide_deal_approval(uuid,text,text)'::regprocedure),E'\r\n',E'\n')) NOT IN ('3e3e5e2b1815bcac5bc28ea679c75f73')
    OR md5(replace(pg_get_functiondef('public.decide_crm_design_task_approval(uuid,text,text)'::regprocedure),E'\r\n',E'\n')) <> '2ff4140400da5c8afe992409ab714eba' THEN
    RAISE EXCEPTION 'Historical CRM approval mutation fingerprint mismatch';
  END IF;
END $guard$;

ALTER TABLE public.crm_deals DROP CONSTRAINT crm_deals_stage_check;
ALTER TABLE public.crm_deals ADD CONSTRAINT crm_deals_stage_check
  CHECK (stage IN ('LEAD','QUALIFICATION','DISCUSSION','PITCH','PROPOSAL','NEGOTIATION','WON','LOST'));
ALTER TABLE public.tasks DROP CONSTRAINT tasks_crm_workflow_kind_check;
ALTER TABLE public.tasks ADD CONSTRAINT tasks_crm_workflow_kind_check
  CHECK (crm_workflow_kind IS NULL OR crm_workflow_kind IN ('CONTACT_DISCUSSION','QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL'));
ALTER TABLE public.crm_generated_tasks DROP CONSTRAINT crm_generated_tasks_kind_check;
ALTER TABLE public.crm_generated_tasks ADD CONSTRAINT crm_generated_tasks_kind_check
  CHECK (kind IN ('CONTACT_DISCUSSION','QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL'));

-- This private, transaction-bound capability can only be minted by the
-- authenticated CRM RPC below. It does not grant list permissions to callers.
-- Managed by the database administrator; no application role may write routes.
CREATE TABLE hrsys_private.crm_quote_proposal_routes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id uuid NOT NULL REFERENCES public.task_lists(id),
  assignee_id uuid NOT NULL REFERENCES public.profiles(id),
  is_active boolean NOT NULL DEFAULT true
);
REVOKE ALL ON hrsys_private.crm_quote_proposal_routes FROM PUBLIC,anon,authenticated,service_role;
-- Seed only a uniquely verified current Production route; ambiguity leaves no route.
INSERT INTO hrsys_private.crm_quote_proposal_routes(list_id,assignee_id)
SELECT l.id,p.id FROM public.task_lists l JOIN public.departments d ON d.id=l.department_id
JOIN public.profiles p ON p.department_id=d.id
WHERE l.name ~* '(design|تصميم)' AND d.is_active IS TRUE AND p.emp_index=8 AND p.is_active IS TRUE
AND (SELECT count(*) FROM public.task_lists WHERE name ~* '(design|تصميم)')=1
AND (SELECT count(*) FROM public.profiles WHERE emp_index=8 AND is_active IS TRUE)=1;
CREATE TABLE hrsys_private.crm_quote_proposal_context (
  backend_pid integer NOT NULL, transaction_id bigint NOT NULL,
  actor_id uuid NOT NULL, deal_id uuid NOT NULL, list_id uuid NOT NULL,
  designer_id uuid NOT NULL, PRIMARY KEY (backend_pid,transaction_id)
);
REVOKE ALL ON hrsys_private.crm_quote_proposal_context FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION hrsys_private.valid_crm_quote_proposal_context(p_deal_id uuid,p_list_id uuid,p_task_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
  SELECT EXISTS (
    SELECT 1 FROM hrsys_private.crm_quote_proposal_context c
     JOIN public.task_lists l ON l.id=c.list_id
     JOIN public.departments department ON department.id=l.department_id
     JOIN public.profiles designer ON designer.id=c.designer_id
    WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current()
      AND c.actor_id=auth.uid() AND c.deal_id=p_deal_id AND c.list_id=p_list_id
      AND designer.is_active IS TRUE
      AND (SELECT count(*) FROM hrsys_private.crm_quote_proposal_routes r WHERE r.is_active)=1
      AND EXISTS (SELECT 1 FROM hrsys_private.crm_quote_proposal_routes r WHERE r.is_active AND r.list_id=c.list_id AND r.assignee_id=c.designer_id)
      AND designer.department_id=l.department_id AND department.is_active IS DISTINCT FROM false
      AND coalesce(l.name,'') ~* '(design|تصميم)'
      AND (p_task_id IS NULL OR EXISTS (SELECT 1 FROM public.crm_generated_tasks m
        WHERE m.task_id=p_task_id AND m.deal_id=c.deal_id AND m.kind='QUOTE_PROPOSAL'))
  );
$body$;
ALTER FUNCTION hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Only the active, current assignee of the registered, non-archived task may
-- access its quotation and proposal sources. This is not a general CRM grant.
CREATE FUNCTION hrsys_private.can_read_quote_proposal_source(p_deal_id uuid,p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
  SELECT p_user_id IS NOT NULL AND p_user_id=auth.uid() AND EXISTS (
    SELECT 1 FROM public.crm_generated_tasks m
      JOIN public.tasks t ON t.id=m.task_id AND t.crm_deal_id=m.deal_id AND t.crm_workflow_kind=m.kind
      JOIN public.profiles p ON p.id=p_user_id
      JOIN public.task_lists l ON l.id=t.task_list_id
      JOIN public.departments department ON department.id=l.department_id
    WHERE m.deal_id=p_deal_id AND m.kind='QUOTE_PROPOSAL' AND t.archived_at IS NULL
      AND p.is_active IS DISTINCT FROM false
      AND p.department_id=l.department_id AND department.is_active IS DISTINCT FROM false AND coalesce(l.name,'') ~* '(design|تصميم)'
      AND (t.assignee_id=p_user_id OR p_user_id=ANY(coalesce(t.assignee_ids,'{}'::uuid[])))
  );
$body$;
ALTER FUNCTION hrsys_private.can_read_quote_proposal_source(uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.can_read_quote_proposal_source(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- The existing assign_task RPC allows a creator to reassign their own task.
-- For this generated task only, accept assignments to active Design-list
-- department members without granting the creator general list access.
CREATE FUNCTION hrsys_private.valid_crm_quote_proposal_reassignment(p_task_id uuid,p_list_id uuid,p_assignees uuid[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
  SELECT auth.uid() IS NOT NULL AND coalesce(public.can_access_crm(auth.uid()),false) AND EXISTS (
    SELECT 1 FROM public.tasks t JOIN public.crm_generated_tasks m ON m.task_id=t.id AND m.deal_id=t.crm_deal_id AND m.kind=t.crm_workflow_kind
      JOIN public.task_lists l ON l.id=t.task_list_id JOIN public.profiles actor ON actor.id=auth.uid()
      JOIN public.departments department ON department.id=l.department_id
    WHERE t.id=p_task_id AND t.task_list_id=p_list_id AND t.crm_workflow_kind='QUOTE_PROPOSAL'
      AND t.archived_at IS NULL AND t.created_by=auth.uid() AND actor.is_active IS DISTINCT FROM false
      AND department.is_active IS DISTINCT FROM false AND coalesce(l.name,'') ~* '(design|تصميم)'
      AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p_assignees,'{}'::uuid[])) candidate(id)
        LEFT JOIN public.profiles p ON p.id=candidate.id
        WHERE p.id IS NULL OR p.is_active IS FALSE OR p.department_id IS DISTINCT FROM l.department_id)
  );
$body$;
ALTER FUNCTION hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[]) FROM PUBLIC,anon,authenticated,service_role;

-- Extend existing guards to cover the new identity without weakening the
-- historical identities, task-list authorization, or MQ-20 protections.
DO $patch$
DECLARE item record; definition text; updated text;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('public.enforce_mq20_task_service_boundaries()', $$IF TG_TABLE_NAME = 'tasks' THEN$$, $$IF TG_TABLE_NAME = 'tasks' THEN
    IF TG_OP='INSERT' AND NEW.crm_workflow_kind='QUOTE_PROPOSAL' AND NEW.created_by=caller_id
       AND NEW.assignee_id=(SELECT c.designer_id FROM hrsys_private.crm_quote_proposal_context c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current())
       AND NEW.assignee_ids=ARRAY[NEW.assignee_id]::uuid[]
       AND hrsys_private.valid_crm_quote_proposal_context(NEW.crm_deal_id,NEW.task_list_id,NEW.id) THEN RETURN NEW; END IF;
    IF TG_OP='UPDATE' AND OLD.crm_workflow_kind='QUOTE_PROPOSAL'
       AND NEW.assignee_id IS NOT DISTINCT FROM (coalesce(NEW.assignee_ids,'{}'::uuid[]))[1]
       AND (to_jsonb(NEW)-ARRAY['assignee_id','assignee_ids','updated_at'])=(to_jsonb(OLD)-ARRAY['assignee_id','assignee_ids','updated_at'])
       AND hrsys_private.valid_crm_quote_proposal_reassignment(OLD.id,OLD.task_list_id,NEW.assignee_ids) THEN RETURN NEW; END IF;$$),
    ('public.ensure_crm_generated_task(uuid,text)', $oldroute$    SELECT count(*) INTO v_list_count FROM public.profiles WHERE emp_index = 8 AND is_active IS DISTINCT FROM false;
    IF v_list_count <> 1 THEN RAISE EXCEPTION 'Configure exactly one active MQ-08 employee' USING ERRCODE = '23514'; END IF;
    SELECT id INTO v_assignee FROM public.profiles WHERE emp_index = 8 AND is_active IS DISTINCT FROM false;
    IF v_assignee IS NULL THEN RAISE EXCEPTION 'Employee MQ-08 must be configured' USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_list_count FROM public.task_lists WHERE COALESCE(name, '') ~* '(design|تصميم)';
    IF v_list_count <> 1 THEN RAISE EXCEPTION 'Configure exactly one Design task list' USING ERRCODE = '23514'; END IF;
    SELECT list.id, department.name INTO v_list, v_department FROM public.task_lists list
      JOIN public.departments department ON department.id = list.department_id
      WHERE COALESCE(list.name, '') ~* '(design|تصميم)';$oldroute$, $newroute$    IF p_kind = 'QUOTE_PROPOSAL' THEN
      SELECT c.list_id,c.designer_id,department.name INTO v_list,v_assignee,v_department
      FROM hrsys_private.crm_quote_proposal_context c JOIN public.task_lists l ON l.id=c.list_id
      JOIN public.departments department ON department.id=l.department_id
      WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current()
        AND hrsys_private.valid_crm_quote_proposal_context(p_deal_id,c.list_id,NULL);
      IF v_list IS NULL OR v_assignee IS NULL THEN RAISE EXCEPTION 'Invalid Design routing context' USING ERRCODE='42501'; END IF;
    ELSE
    SELECT count(*) INTO v_list_count FROM public.profiles WHERE emp_index = 8 AND is_active IS DISTINCT FROM false;
    IF v_list_count <> 1 THEN RAISE EXCEPTION 'Configure exactly one active MQ-08 employee' USING ERRCODE = '23514'; END IF;
    SELECT id INTO v_assignee FROM public.profiles WHERE emp_index = 8 AND is_active IS DISTINCT FROM false;
    IF v_assignee IS NULL THEN RAISE EXCEPTION 'Employee MQ-08 must be configured' USING ERRCODE = '23514'; END IF;
    SELECT count(*) INTO v_list_count FROM public.task_lists WHERE COALESCE(name, '') ~* '(design|تصميم)';
    IF v_list_count <> 1 THEN RAISE EXCEPTION 'Configure exactly one Design task list' USING ERRCODE = '23514'; END IF;
    SELECT list.id, department.name INTO v_list, v_department FROM public.task_lists list
      JOIN public.departments department ON department.id = list.department_id
      WHERE COALESCE(list.name, '') ~* '(design|تصميم)';
    END IF;$newroute$),
    ('public.ensure_crm_generated_task(uuid,text)', $$p_kind = 'QUOTE_PROPOSAL_DESIGN'$$, $$p_kind IN ('QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL')$$),
    ('public.ensure_crm_generated_task(uuid,text)', $$NOT COALESCE(public.can_add_task_to_list(v_list, auth.uid()), false)$$, $$(NOT COALESCE(public.can_add_task_to_list(v_list, auth.uid()), false) AND NOT (p_kind='QUOTE_PROPOSAL' AND hrsys_private.valid_crm_quote_proposal_context(p_deal_id,v_list,NULL)))$$),
    ('public.protect_crm_generated_task_identity()', $$'CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN'$$, $$'CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN', 'QUOTE_PROPOSAL'$$),
    ('public.enforce_task_completion_approval()', $$'CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN'$$, $$'CONTACT_DISCUSSION', 'QUOTE_PROPOSAL_DESIGN', 'QUOTE_PROPOSAL'$$),
    ('public.enforce_marketing_design_review()', $$NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'$$, $$NEW.crm_workflow_kind IN ('QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL')$$),
    ('public.enforce_crm_design_task_completion()', $$NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'$$, $$NEW.crm_workflow_kind IN ('QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL')$$),
    ('public.enforce_private_task_list_ownership()', $$NOT COALESCE(public.can_add_task_to_list(NEW.task_list_id, auth.uid()), false)$$, $$(NOT COALESCE(public.can_add_task_to_list(NEW.task_list_id, auth.uid()), false) AND NOT COALESCE(((TG_OP='INSERT' AND NEW.crm_workflow_kind='QUOTE_PROPOSAL' AND NEW.created_by=auth.uid() AND NEW.assignee_id=(SELECT c.designer_id FROM hrsys_private.crm_quote_proposal_context c WHERE c.backend_pid=pg_backend_pid() AND c.transaction_id=txid_current()) AND NEW.assignee_ids=ARRAY[NEW.assignee_id]::uuid[] AND hrsys_private.valid_crm_quote_proposal_context(NEW.crm_deal_id,NEW.task_list_id,NEW.id)) OR (TG_OP='UPDATE' AND NEW.assignee_id IS NOT DISTINCT FROM (coalesce(NEW.assignee_ids,'{}'::uuid[]))[1] AND (to_jsonb(NEW)-ARRAY['assignee_id','assignee_ids','updated_at'])=(to_jsonb(OLD)-ARRAY['assignee_id','assignee_ids','updated_at']) AND hrsys_private.valid_crm_quote_proposal_reassignment(OLD.id,OLD.task_list_id,NEW.assignee_ids))),false))$$),
    ('public.list_crm_deal_attachments_secure(uuid)', $$AND auth.uid() IS NOT NULL AND public.can_access_crm(auth.uid())$$, $$AND auth.uid() IS NOT NULL AND (public.can_access_crm(auth.uid()) OR (attachment.category IN ('QUOTATION','PROPOSAL') AND hrsys_private.can_read_quote_proposal_source(attachment.deal_id,auth.uid())))$$),
    ('public.can_read_crm_deal_file(text,uuid)', $$IF public.can_access_crm(p_user_id) THEN RETURN true; END IF;$$, $$IF public.can_access_crm(p_user_id) THEN RETURN true; END IF;
  IF EXISTS (SELECT 1 FROM public.crm_deal_attachments attachment WHERE attachment.file_url='storage://crm-deal-files/' || p_object_name
      AND attachment.is_archived=false AND attachment.category IN ('QUOTATION','PROPOSAL')
      AND hrsys_private.can_read_quote_proposal_source(attachment.deal_id,p_user_id)) THEN RETURN true; END IF;$$),
    ('public.can_access_task(uuid,uuid)', $$task.created_by = p_user_id$$, $$(task.created_by = p_user_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.can_view_task(uuid,uuid)', $$p_user_id IN (t.created_by, t.assignee_id, t.supervisor_id)$$, $$(p_user_id IN (t.assignee_id, t.supervisor_id) OR (p_user_id=t.created_by AND coalesce(t.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL'))$$),
    ('public.can_manage_task(uuid,uuid)', $$task.created_by = p_user_id$$, $$(task.created_by = p_user_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.can_manage_task_attachments(uuid,uuid)', $$task.created_by = p_user_id$$, $$(task.created_by = p_user_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.change_task_status(uuid,text)', $$profile.id IN (task_row.created_by, task_row.assignee_id, task_row.supervisor_id)$$, $$(profile.id IN (task_row.assignee_id, task_row.supervisor_id) OR (profile.id=task_row.created_by AND coalesce(task_row.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL'))$$),
    ('public.can_delete_task(uuid,uuid)', $$task.created_by = p_user_id$$, $$(task.created_by = p_user_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.can_execute_task(uuid,uuid)', $$profile.id IN (task.created_by, task.assignee_id, task.supervisor_id)$$, $$(profile.id IN (task.assignee_id, task.supervisor_id) OR (profile.id=task.created_by AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL'))$$),
    ('public.delete_task_secure(uuid)', $$v_task.created_by = auth.uid()$$, $$(v_task.created_by = auth.uid() AND coalesce(v_task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.task_belongs_to_employee(uuid,uuid)', $$task.created_by = p_employee_id$$, $$(task.created_by = p_employee_id AND coalesce(task.crm_workflow_kind,'') <> 'QUOTE_PROPOSAL')$$),
    ('public.sync_crm_design_task_status()', $$NEW.crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL_DESIGN'$$, $$(NEW.crm_workflow_kind IS NULL OR NEW.crm_workflow_kind NOT IN ('QUOTE_PROPOSAL_DESIGN','QUOTE_PROPOSAL'))$$)
  ) x(signature,old_text,new_text) LOOP
    definition := pg_get_functiondef(to_regprocedure(item.signature));
    updated := replace(definition,item.old_text,item.new_text);
    IF updated = definition THEN RAISE EXCEPTION 'Expected guard insertion point missing: %',item.signature; END IF;
    EXECUTE updated;
  END LOOP;
END $patch$;
ALTER POLICY tasks_select_own_created ON public.tasks
  USING (created_by=auth.uid() AND crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL');

CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
DECLARE ready boolean;
BEGIN
  IF NEW.stage = 'LOST' AND NULLIF(BTRIM(COALESCE(NEW.lost_reason,'')),'') IS NULL THEN
    RAISE EXCEPTION 'A lost reason is required' USING ERRCODE='23514';
  END IF;
  IF TG_OP='INSERT' THEN
    IF NEW.stage <> 'LEAD' THEN RAISE EXCEPTION 'New deals must start in Lead' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.stage IS NOT DISTINCT FROM OLD.stage THEN RETURN NEW; END IF;
  IF auth.uid() IS NOT NULL AND (
      NOT coalesce(public.can_access_crm(auth.uid()),false)
      OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false)
      OR (auth.uid() IS DISTINCT FROM OLD.created_by AND auth.uid() IS DISTINCT FROM OLD.assigned_to
          AND NOT auth.uid()=ANY(coalesce(OLD.assignee_ids,'{}'::uuid[])))) THEN
    RAISE EXCEPTION 'Deal assignment required' USING ERRCODE='42501';
  END IF;
  IF OLD.stage='LEAD' AND NEW.stage='QUALIFICATION' THEN RETURN NEW; END IF;
  IF OLD.stage='QUALIFICATION' AND NEW.stage='DISCUSSION' THEN RETURN NEW; END IF;
  IF OLD.stage='DISCUSSION' AND NEW.stage='NEGOTIATION' THEN
    SELECT EXISTS (SELECT 1 FROM public.crm_generated_tasks m JOIN public.tasks t ON t.id=m.task_id
      WHERE m.deal_id=OLD.id AND m.kind='QUOTE_PROPOSAL' AND t.crm_deal_id=OLD.id
        AND t.crm_workflow_kind='QUOTE_PROPOSAL' AND t.archived_at IS NULL
        AND lower(btrim(t.status))='completed') INTO ready;
    IF NOT ready THEN RAISE EXCEPTION 'Complete the registered Quote & Proposal task first' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF OLD.stage='NEGOTIATION' AND NEW.stage='LOST' THEN RETURN NEW; END IF;
  IF OLD.stage='NEGOTIATION' AND NEW.stage='WON' AND EXISTS (
      SELECT 1 FROM public.projects WHERE deal_id=OLD.id AND source='WON_DEAL') THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Invalid CRM stage transition' USING ERRCODE='23514';
END $body$;

CREATE OR REPLACE FUNCTION public.change_crm_deal_stage(p_deal_id uuid,p_new_stage text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
DECLARE d public.crm_deals%ROWTYPE; next_stage text := upper(btrim(coalesce(p_new_stage,''))); task_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT coalesce(public.can_access_crm(auth.uid()),false)
    OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE='42501'; END IF;
  IF next_stage NOT IN ('QUALIFICATION','DISCUSSION','NEGOTIATION') THEN
    RAISE EXCEPTION 'Use the dedicated order or lost workflow' USING ERRCODE='22023'; END IF;
  SELECT * INTO d FROM public.crm_deals WHERE id=p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE='P0002'; END IF;
  IF auth.uid() IS DISTINCT FROM d.created_by AND auth.uid() IS DISTINCT FROM d.assigned_to
      AND NOT auth.uid()=ANY(coalesce(d.assignee_ids,'{}'::uuid[])) THEN
    RAISE EXCEPTION 'Deal assignment required' USING ERRCODE='42501'; END IF;
  IF d.stage IS DISTINCT FROM next_stage THEN
    UPDATE public.crm_deals SET stage=next_stage WHERE id=p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id,action,from_status,to_status,actor_id)
      VALUES(p_deal_id,'STAGE_CHANGED',d.stage,next_stage,auth.uid());
  END IF;
  IF next_stage='QUALIFICATION' THEN task_id := public.create_crm_contact_discussion_task(p_deal_id); END IF;
  RETURN jsonb_build_object('deal_id',p_deal_id,'from_stage',d.stage,'to_stage',next_stage,'task_id',task_id,'actor_id',auth.uid());
END $body$;

CREATE FUNCTION public.start_crm_quote_proposal(p_deal_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
DECLARE d public.crm_deals%ROWTYPE; task_id uuid; already_registered boolean; list_id uuid; designer_id uuid; n integer;
BEGIN
  IF auth.uid() IS NULL OR NOT coalesce(public.can_access_crm(auth.uid()),false)
    OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO d FROM public.crm_deals WHERE id=p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE='P0002'; END IF;
  IF auth.uid() IS DISTINCT FROM d.created_by AND auth.uid() IS DISTINCT FROM d.assigned_to
      AND NOT auth.uid()=ANY(coalesce(d.assignee_ids,'{}'::uuid[])) THEN
    RAISE EXCEPTION 'Deal assignment required' USING ERRCODE='42501'; END IF;
  IF d.stage<>'DISCUSSION' THEN RAISE EXCEPTION 'Deal must be in Discussion' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id=p_deal_id AND category='QUOTATION' AND is_archived=false AND nullif(btrim(file_url),'') IS NOT NULL)
     OR NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id=p_deal_id AND category='PROPOSAL' AND is_archived=false AND nullif(btrim(file_url),'') IS NOT NULL AND nullif(btrim(description),'') IS NOT NULL AND file_type LIKE 'image/%') THEN
    RAISE EXCEPTION 'Quote and described proposal image are required' USING ERRCODE='23514'; END IF;
  IF EXISTS (SELECT 1 FROM public.crm_generated_tasks WHERE deal_id=p_deal_id AND kind='QUOTE_PROPOSAL_DESIGN') THEN
    RAISE EXCEPTION 'Historical Design mapping requires review' USING ERRCODE='23514'; END IF;
  SELECT count(*) INTO n FROM hrsys_private.crm_quote_proposal_routes WHERE is_active;
  IF n<>1 THEN RAISE EXCEPTION 'Configure exactly one active Design route' USING ERRCODE='23514'; END IF;
  SELECT r.list_id,r.assignee_id INTO list_id,designer_id FROM hrsys_private.crm_quote_proposal_routes r WHERE r.is_active;
  IF NOT EXISTS (SELECT 1 FROM public.task_lists l JOIN public.profiles p ON p.id=designer_id JOIN public.departments department ON department.id=l.department_id
    WHERE l.id=list_id AND p.is_active IS TRUE AND p.department_id=l.department_id AND department.is_active IS TRUE AND coalesce(l.name,'') ~* '(design|تصميم)') THEN
    RAISE EXCEPTION 'Design list and designer department mismatch' USING ERRCODE='23514'; END IF;
  SELECT EXISTS(SELECT 1 FROM public.crm_generated_tasks WHERE deal_id=p_deal_id AND kind='QUOTE_PROPOSAL') INTO already_registered;
  INSERT INTO hrsys_private.crm_quote_proposal_context(backend_pid,transaction_id,actor_id,deal_id,list_id,designer_id)
    VALUES(pg_backend_pid(),txid_current(),auth.uid(),p_deal_id,list_id,designer_id);
  task_id := public.ensure_crm_generated_task(p_deal_id,'QUOTE_PROPOSAL');
  DELETE FROM hrsys_private.crm_quote_proposal_context WHERE backend_pid=pg_backend_pid() AND transaction_id=txid_current();
  IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE id=task_id AND crm_deal_id=p_deal_id AND crm_workflow_kind='QUOTE_PROPOSAL' AND archived_at IS NULL) THEN
    RAISE EXCEPTION 'Generated task identity mismatch' USING ERRCODE='23514'; END IF;
  UPDATE public.crm_deals SET design_task_id=task_id,approval_type='QUOTE_PROPOSAL',workflow_status='DESIGN_IN_PROGRESS',proposal_sent_at=coalesce(proposal_sent_at,now()) WHERE id=p_deal_id;
  IF NOT already_registered THEN
    INSERT INTO public.crm_deal_activity(deal_id,action,note,actor_id) VALUES(p_deal_id,'QUOTE_PROPOSAL_STARTED',task_id::text,auth.uid());
  END IF;
  RETURN task_id;
END $body$;
ALTER FUNCTION public.start_crm_quote_proposal(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.start_crm_quote_proposal(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.start_crm_quote_proposal(uuid) TO authenticated,service_role;
CREATE FUNCTION public.submit_crm_quote_proposal_files(p_task_id uuid,p_links text[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $body$
DECLARE task_row public.tasks%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false) THEN
    RAISE EXCEPTION 'Active user required' USING ERRCODE='42501'; END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id=p_task_id FOR UPDATE;
  IF NOT FOUND OR task_row.crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL' OR task_row.archived_at IS NOT NULL
     OR lower(btrim(coalesce(task_row.status,'')))='completed'
     OR NOT EXISTS (SELECT 1 FROM public.crm_generated_tasks WHERE task_id=p_task_id AND deal_id=task_row.crm_deal_id AND kind='QUOTE_PROPOSAL')
     OR NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id=task_row.crm_deal_id AND stage='DISCUSSION')
     OR (auth.uid() IS DISTINCT FROM task_row.assignee_id AND NOT auth.uid()=ANY(coalesce(task_row.assignee_ids,'{}'::uuid[]))) THEN
    RAISE EXCEPTION 'Assigned Quote & Proposal task required' USING ERRCODE='42501'; END IF;
  IF p_links IS NULL OR EXISTS (SELECT 1 FROM unnest(p_links) link WHERE NOT EXISTS (
     SELECT 1 FROM public.task_attachments attachment WHERE attachment.task_id=p_task_id AND attachment.file_url=link
       AND attachment.is_archived=false AND (attachment.file_type='application/pdf' OR attachment.file_type LIKE 'image/%'))) THEN
    RAISE EXCEPTION 'Registered Design PDF or image required' USING ERRCODE='23514'; END IF;
  UPDATE public.tasks SET submission_links=p_links,upload_link=p_links[1] WHERE id=p_task_id;
END $body$;
ALTER FUNCTION public.submit_crm_quote_proposal_files(uuid,text[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.submit_crm_quote_proposal_files(uuid,text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.submit_crm_quote_proposal_files(uuid,text[]) TO authenticated,service_role;
-- Historical approval rows remain readable; stop starting or deciding new
-- CRM approval cycles through the old authenticated entry points.
REVOKE EXECUTE ON FUNCTION public.start_deal_approval(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.start_crm_presentation_approval(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.decide_deal_approval(uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.decide_crm_design_task_approval(uuid,text,text) FROM PUBLIC,anon,authenticated;
DO $post$ BEGIN
  IF has_function_privilege('anon','public.start_crm_quote_proposal(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.start_crm_quote_proposal(uuid)','EXECUTE')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.start_crm_quote_proposal(uuid)'::regprocedure AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp']) THEN
    RAISE EXCEPTION 'Quote & Proposal security postcondition mismatch';
  END IF;
  IF has_function_privilege('anon','public.submit_crm_quote_proposal_files(uuid,text[])','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.submit_crm_quote_proposal_files(uuid,text[])','EXECUTE')
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.submit_crm_quote_proposal_files(uuid,text[])'::regprocedure AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp'])
     OR has_table_privilege('authenticated','hrsys_private.crm_quote_proposal_context','INSERT')
     OR has_table_privilege('anon','hrsys_private.crm_quote_proposal_context','INSERT')
     OR has_function_privilege('authenticated','hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','hrsys_private.can_read_quote_proposal_source(uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','hrsys_private.can_read_quote_proposal_source(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[])','EXECUTE')
     OR has_function_privilege('anon','hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[])','EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_proc WHERE oid IN ('hrsys_private.valid_crm_quote_proposal_context(uuid,uuid,uuid)'::regprocedure,'hrsys_private.valid_crm_quote_proposal_reassignment(uuid,uuid,uuid[])'::regprocedure,'hrsys_private.can_read_quote_proposal_source(uuid,uuid)'::regprocedure)
       AND (proowner<>'postgres'::regrole OR NOT prosecdef OR proconfig<>ARRAY['search_path=public, pg_temp']))
     OR has_table_privilege('authenticated','public.projects','SELECT') THEN
    RAISE EXCEPTION 'Submission or project security postcondition mismatch';
  END IF;
  IF has_function_privilege('authenticated','public.start_deal_approval(uuid,uuid,uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.start_crm_presentation_approval(uuid,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.decide_deal_approval(uuid,text,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.decide_crm_design_task_approval(uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Obsolete CRM approval entry point remains executable';
  END IF;
END $post$;
COMMIT;
