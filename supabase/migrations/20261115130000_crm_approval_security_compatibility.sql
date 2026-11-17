-- Draft only. Preserve the current three approval slots and record each
-- previously decided step in the existing CRM activity feed before restart.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DO $migration$
DECLARE
  start_oid oid := to_regprocedure('public.start_deal_approval(uuid,uuid,uuid,uuid)');
  decide_oid oid := to_regprocedure('public.decide_deal_approval(uuid,text,text)');
  start_def text; decide_def text; original text; replacement text; design_def text;
  staging_case boolean;
BEGIN
  IF current_user <> 'postgres' OR current_database() <> 'postgres'
    OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
    OR start_oid IS NULL OR decide_oid IS NULL
    OR md5(pg_get_functiondef(start_oid)) <> 'dcb3e4a763f0183be2bc56915732c3bd'
    OR md5(pg_get_functiondef(decide_oid)) <> '3e3e5e2b1815bcac5bc28ea679c75f73'
    OR md5(pg_get_functiondef('public.can_access_crm(uuid)'::regprocedure)) <> '9bbf7402dfaf581ab81a38ad05452628'
    OR md5(pg_get_functiondef('public.is_crm_approval_admin(uuid)'::regprocedure)) <> 'cd7202ee22cec060c0a090ef8d882f26'
    OR md5(pg_get_functiondef('public.can_view_business_financials(uuid)'::regprocedure)) <> 'c29d57300ba3436d10a1632d661ebf98'
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_view_business_financials(uuid)'::regprocedure
       AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp']::text[])
    OR has_function_privilege('anon','public.can_view_business_financials(uuid)','execute')
    OR NOT has_function_privilege('authenticated','public.can_view_business_financials(uuid)','execute')
    OR NOT has_function_privilege('service_role','public.can_view_business_financials(uuid)','execute')
    OR EXISTS (SELECT 1 FROM pg_proc WHERE oid IN (start_oid,decide_oid) AND
       (proowner<>'postgres'::regrole OR NOT prosecdef OR proconfig IS DISTINCT FROM ARRAY['search_path=public, pg_temp']::text[]))
    OR has_function_privilege('anon',start_oid,'execute') OR has_function_privilege('anon',decide_oid,'execute')
    OR NOT has_function_privilege('service_role',start_oid,'execute') OR NOT has_function_privilege('service_role',decide_oid,'execute')
    OR to_regprocedure('public.crm_current_user_is_approval_assignee(uuid)') IS NOT NULL
    OR to_regprocedure('public.list_my_pending_crm_approval_context()') IS NOT NULL
    OR to_regprocedure('public.list_my_pending_crm_approval_documents()') IS NOT NULL
    OR to_regprocedure('public.get_my_pending_crm_approval_document(uuid,text)') IS NOT NULL
    OR to_regclass('storage.objects') IS NULL
    OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role' AND rolbypassrls)
    OR NOT has_table_privilege('service_role',to_regclass('storage.objects'),'SELECT')
    OR NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.crm_deal_approval_steps'::regclass AND relrowsecurity)
    OR NOT has_table_privilege('authenticated','public.crm_deal_approval_steps','SELECT') THEN
    RAISE EXCEPTION 'Approval prerequisites differ from the reviewed baseline';
  END IF;
  staging_case := NOT has_function_privilege('authenticated',start_oid,'execute');
  IF has_function_privilege('authenticated',decide_oid,'execute') = staging_case THEN
    RAISE EXCEPTION 'Approval RPC grants do not match either reviewed environment';
  END IF;
  IF staging_case THEN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='crm_deal_approval_steps'
      AND policyname='Authenticated users can view deal approvals' AND cmd='SELECT' AND permissive='PERMISSIVE'
      AND roles=ARRAY['authenticated']::name[] AND qual='true') THEN
      RAISE EXCEPTION 'Staging approval read policy differs';
    END IF;
    -- Remove only the reviewed blanket policies; retain the independently
    -- scoped CRM and project-sharing policies. Abort on any catalog drift.
    IF (SELECT count(*) FROM pg_policies p JOIN (VALUES
      ('crm_deal_activity','Authenticated users can view deal activity','b326b5062b2f0e69046810717534cb09'),
      ('crm_deal_attachments','Authenticated users can view deal attachments','b326b5062b2f0e69046810717534cb09'),
      ('crm_deal_activity','crm_authorized_activity_select','eb8c3613925a4ec015c5b577a9f8f737'),
      ('crm_deal_attachments','crm_authorized_attachments_select','62764aebd28b1ac38c5f3b11558e7bf2'),
      ('crm_deal_attachments','crm_project_shared_attachments_select','d365bd9a306d4684348c68de08c83cc3')
    ) AS expected(tbl,policy,hash) ON p.tablename=expected.tbl AND p.policyname=expected.policy
      WHERE p.schemaname='public' AND p.permissive='PERMISSIVE' AND p.cmd='SELECT'
      AND p.roles=ARRAY['authenticated']::name[] AND md5(p.qual)=expected.hash AND p.with_check IS NULL) <> 5
      OR EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname='public'
        AND p.tablename IN ('crm_deal_activity','crm_deal_attachments') AND p.permissive='PERMISSIVE'
        AND p.cmd IN ('SELECT','ALL') AND p.qual IN ('true','(true)')
        AND p.policyname NOT IN ('Authenticated users can view deal activity','Authenticated users can view deal attachments')) THEN
      RAISE EXCEPTION 'Staging CRM read policies differ from the reviewed baseline';
    END IF;
    DROP POLICY "Authenticated users can view deal activity" ON public.crm_deal_activity;
    DROP POLICY "Authenticated users can view deal attachments" ON public.crm_deal_attachments;
    DROP POLICY "Authenticated users can view deal approvals" ON public.crm_deal_approval_steps;
    -- The legacy approval creator must register the new identity before the
    -- existing BEFORE INSERT guard checks it; the task FK is deferred.
    IF md5(pg_get_functiondef('public.create_crm_design_task_for_deal(uuid)'::regprocedure)) <> 'c26dd911582fffb86c61c9cdd8843069'
      OR md5(pg_get_functiondef('public.protect_crm_generated_task_identity()'::regprocedure)) <> 'f87b9f595740451bae82009de5243555'
      OR EXISTS (SELECT 1 FROM pg_proc WHERE oid IN ('public.create_crm_design_task_for_deal(uuid)'::regprocedure,'public.protect_crm_generated_task_identity()'::regprocedure)
        AND (proowner <> 'postgres'::regrole OR NOT prosecdef OR proconfig IS DISTINCT FROM ARRAY['search_path=public, pg_temp']::text[]))
      OR has_function_privilege('anon','public.create_crm_design_task_for_deal(uuid)','execute')
      OR has_function_privilege('authenticated','public.create_crm_design_task_for_deal(uuid)','execute')
      OR NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.tasks'::regclass AND t.tgname='protect_crm_generated_task_identity'
        AND t.tgenabled='O' AND t.tgfoid='public.protect_crm_generated_task_identity()'::regprocedure)
      OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.crm_generated_tasks'::regclass
        AND c.contype='f' AND c.confrelid='public.tasks'::regclass AND c.condeferrable AND c.condeferred) THEN
      RAISE EXCEPTION 'Staging Design identity prerequisites differ';
    END IF;
    design_def := replace(replace(pg_get_functiondef('public.create_crm_design_task_for_deal(uuid)'::regprocedure), E'\r\n', E'\n'), E'\r', E'\n');
    original := replace(replace($old$    PERFORM set_config('app.crm_design_task_creation', 'on', true);
    INSERT INTO public.tasks(
        title,$old$, E'\r\n', E'\n'), E'\r', E'\n');
    replacement := replace(replace($new$    PERFORM set_config('app.crm_design_task_creation', 'on', true);
    v_task_id := gen_random_uuid();
    INSERT INTO public.crm_generated_tasks(deal_id,kind,task_id)
    VALUES (p_deal_id,'QUOTE_PROPOSAL_DESIGN',v_task_id);
    INSERT INTO public.tasks(
        id, title,$new$, E'\r\n', E'\n'), E'\r', E'\n');
    IF (length(design_def)-length(replace(design_def,original,'')))/length(original) <> 1 THEN
      RAISE EXCEPTION 'Staging Design creation template differs';
    END IF;
    design_def := replace(design_def,original,replacement);
    original := replace(replace($old$    ) VALUES (
        'Design approved proposal: ' || v_deal.title,$old$, E'\r\n', E'\n'), E'\r', E'\n');
    replacement := replace(replace($new$    ) VALUES (
        v_task_id, 'Design approved proposal: ' || v_deal.title,$new$, E'\r\n', E'\n'), E'\r', E'\n');
    IF (length(design_def)-length(replace(design_def,original,'')))/length(original) <> 1 THEN
      RAISE EXCEPTION 'Staging Design insertion template differs';
    END IF;
    EXECUTE replace(design_def,original,replacement);
  ELSIF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='crm_deal_approval_steps'
      AND permissive='PERMISSIVE' AND cmd IN ('SELECT','ALL') AND qual IN ('true','(true)')) THEN
    RAISE EXCEPTION 'Unexpected broad Production approval policy';
  END IF;
  IF NOT staging_case THEN
    -- Production has no legacy generated-task identity trigger. Protect only
    -- newly inserted Design identities and leave historical task identities intact.
    IF md5(pg_get_functiondef('public.create_crm_design_task_for_deal(uuid)'::regprocedure)) <> 'c26dd911582fffb86c61c9cdd8843069'
      OR to_regprocedure('public.guard_crm_design_task_identity()') IS NOT NULL
      OR to_regprocedure('public.protect_crm_generated_task_identity()') IS NOT NULL
      OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass AND tgname='crm_design_identity_guard' AND NOT tgisinternal)
      OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.create_crm_design_task_for_deal(uuid)'::regprocedure
        AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp']::text[])
      OR has_function_privilege('anon','public.create_crm_design_task_for_deal(uuid)','execute')
      OR NOT has_function_privilege('authenticated','public.create_crm_design_task_for_deal(uuid)','execute')
      OR NOT has_function_privilege('service_role','public.create_crm_design_task_for_deal(uuid)','execute')
      OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='public.crm_generated_tasks'::regclass
        AND c.contype='f' AND c.confrelid='public.tasks'::regclass AND c.condeferrable AND c.condeferred) THEN
      RAISE EXCEPTION 'Production Design identity prerequisites differ';
    END IF;
    design_def := replace(replace(pg_get_functiondef('public.create_crm_design_task_for_deal(uuid)'::regprocedure), E'\r\n', E'\n'), E'\r', E'\n');
    original := replace(replace($old$    PERFORM set_config('app.crm_design_task_creation', 'on', true);
    INSERT INTO public.tasks(
        title,$old$, E'\r\n', E'\n'), E'\r', E'\n');
    replacement := replace(replace($new$    PERFORM set_config('app.crm_design_task_creation', 'on', true);
    v_task_id := gen_random_uuid();
    INSERT INTO public.crm_generated_tasks(deal_id,kind,task_id)
    VALUES (p_deal_id,'QUOTE_PROPOSAL_DESIGN',v_task_id);
    INSERT INTO public.tasks(
        id, title,$new$, E'\r\n', E'\n'), E'\r', E'\n');
    IF (length(design_def)-length(replace(design_def,original,'')))/length(original) <> 1 THEN
      RAISE EXCEPTION 'Production Design creation template differs';
    END IF;
    design_def := replace(design_def,original,replacement);
    original := replace(replace($old$    ) VALUES (
        'Design approved proposal: ' || v_deal.title,$old$, E'\r\n', E'\n'), E'\r', E'\n');
    replacement := replace(replace($new$    ) VALUES (
        v_task_id, 'Design approved proposal: ' || v_deal.title,$new$, E'\r\n', E'\n'), E'\r', E'\n');
    IF (length(design_def)-length(replace(design_def,original,'')))/length(original) <> 1 THEN
      RAISE EXCEPTION 'Production Design insertion template differs';
    END IF;
    EXECUTE replace(design_def,original,replacement);
    EXECUTE replace(replace($ddl$
      CREATE FUNCTION public.guard_crm_design_task_identity() RETURNS trigger
      LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
      AS $body$
      BEGIN
        IF TG_OP='UPDATE' THEN
          -- Preserve the existing deal-deletion FK detach path only after the
          -- referenced deal is actually gone, as the Staging guard does.
          IF NEW.crm_deal_id IS NULL AND OLD.crm_deal_id IS NOT NULL
             AND NEW.crm_workflow_kind IS NOT DISTINCT FROM OLD.crm_workflow_kind
             AND NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id=OLD.crm_deal_id) THEN
            RETURN NEW;
          END IF;
          IF (OLD.crm_workflow_kind='QUOTE_PROPOSAL_DESIGN' OR NEW.crm_workflow_kind='QUOTE_PROPOSAL_DESIGN')
             AND (NEW.crm_deal_id IS DISTINCT FROM OLD.crm_deal_id OR NEW.crm_workflow_kind IS DISTINCT FROM OLD.crm_workflow_kind) THEN
            RAISE EXCEPTION 'Design task identity is protected' USING ERRCODE='42501';
          END IF;
          RETURN NEW;
        END IF;
        IF NEW.crm_workflow_kind='QUOTE_PROPOSAL_DESIGN' AND NOT EXISTS (
          SELECT 1 FROM public.crm_generated_tasks m WHERE m.deal_id=NEW.crm_deal_id
          AND m.kind=NEW.crm_workflow_kind AND m.task_id=NEW.id) THEN
          RAISE EXCEPTION 'Design tasks must be generated by the CRM workflow' USING ERRCODE='42501';
        END IF;
        RETURN NEW;
      END;
      $body$
    $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
    ALTER FUNCTION public.guard_crm_design_task_identity() OWNER TO postgres;
    REVOKE ALL ON FUNCTION public.guard_crm_design_task_identity() FROM PUBLIC,anon,authenticated,service_role;
    CREATE TRIGGER crm_design_identity_guard BEFORE INSERT OR UPDATE OF crm_deal_id,crm_workflow_kind ON public.tasks
      FOR EACH ROW EXECUTE FUNCTION public.guard_crm_design_task_identity();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='crm_deal_approval_steps'
    AND policyname='crm_authorized_approval_steps_select' AND md5(qual)='eb8c3613925a4ec015c5b577a9f8f737') THEN
    RAISE EXCEPTION 'Scoped CRM approval policy differs';
  END IF;
  -- A pending Design decision may not reopen a terminal deal. Lock the deal
  -- before the decision row, then revalidate both assignment and terminal state.
  IF md5(pg_get_functiondef('public.decide_crm_design_task_approval(uuid,text,text)'::regprocedure)) <> '2ff4140400da5c8afe992409ab714eba'
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.decide_crm_design_task_approval(uuid,text,text)'::regprocedure
      AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp']::text[])
    OR has_function_privilege('anon','public.decide_crm_design_task_approval(uuid,text,text)','execute')
    OR NOT has_function_privilege('authenticated','public.decide_crm_design_task_approval(uuid,text,text)','execute')
    OR NOT has_function_privilege('service_role','public.decide_crm_design_task_approval(uuid,text,text)','execute') THEN
    RAISE EXCEPTION 'Design approval decision prerequisites differ';
  END IF;
  design_def := replace(replace(pg_get_functiondef('public.decide_crm_design_task_approval(uuid,text,text)'::regprocedure), E'\r\n', E'\n'), E'\r', E'\n');
  original := replace(replace($old$    SELECT * INTO v_step FROM public.crm_design_task_approval_steps WHERE id = p_step_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Design approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;$old$, E'\r\n', E'\n'), E'\r', E'\n');
  replacement := replace(replace($new$    SELECT * INTO v_step FROM public.crm_design_task_approval_steps WHERE id = p_step_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Design approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id=v_step.deal_id FOR UPDATE;
    IF NOT FOUND OR UPPER(COALESCE(v_deal.stage,'')) IN ('WON','LOST') THEN
        RAISE EXCEPTION 'Design approval unavailable for a terminal deal' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_step FROM public.crm_design_task_approval_steps WHERE id=p_step_id AND deal_id=v_deal.id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Design approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;$new$, E'\r\n', E'\n'), E'\r', E'\n');
  IF (length(design_def)-length(replace(design_def,original,'')))/length(original) <> 1 THEN
    RAISE EXCEPTION 'Design approval decision template differs';
  END IF;
  EXECUTE replace(design_def,original,replacement);
  -- Authenticated callers may ask only about themselves; the trusted
  -- service role retains its existing server-side cross-user capability.
  IF md5(pg_get_functiondef('public.can_read_crm_deal_file(text,uuid)'::regprocedure)) <> 'ffe59b1b1f8671325a009549a2755691'
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_read_crm_deal_file(text,uuid)'::regprocedure
      AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=public, pg_temp']::text[])
    OR has_function_privilege('anon','public.can_read_crm_deal_file(text,uuid)','execute')
    OR NOT has_function_privilege('authenticated','public.can_read_crm_deal_file(text,uuid)','execute')
    OR NOT has_function_privilege('service_role','public.can_read_crm_deal_file(text,uuid)','execute') THEN
    RAISE EXCEPTION 'CRM file authorization helper differs';
  END IF;
  design_def := replace(replace(pg_get_functiondef('public.can_read_crm_deal_file(text,uuid)'::regprocedure), E'\r\n', E'\n'), E'\r', E'\n');
  original := replace(replace($old$BEGIN
  IF public.can_access_crm(p_user_id) THEN RETURN true; END IF;$old$, E'\r\n', E'\n'), E'\r', E'\n');
  replacement := replace(replace($new$BEGIN
  IF p_user_id IS DISTINCT FROM auth.uid() AND current_setting('role',true) IS DISTINCT FROM 'service_role' THEN
    RETURN false;
  END IF;
  IF public.can_access_crm(p_user_id) THEN RETURN true; END IF;$new$, E'\r\n', E'\n'), E'\r', E'\n');
  IF (length(design_def)-length(replace(design_def,original,'')))/length(original) <> 1 THEN
    RAISE EXCEPTION 'CRM file authorization helper template differs';
  END IF;
  EXECUTE replace(design_def,original,replacement);
  -- Evaluate only the existing project-assignee relationship with the caller's
  -- identity; this does not grant SELECT on projects or accept a user ID.
  IF to_regprocedure('public.crm_current_user_can_read_project_shared_attachment(uuid)') IS NOT NULL
    OR NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='crm_deal_attachments'
      AND policyname='crm_project_shared_attachments_select' AND permissive='PERMISSIVE' AND cmd='SELECT'
      AND roles=ARRAY['authenticated']::name[] AND md5(qual)='d365bd9a306d4684348c68de08c83cc3' AND with_check IS NULL) THEN
    RAISE EXCEPTION 'Project-shared attachment policy differs from the reviewed baseline';
  END IF;
  EXECUTE replace(replace($ddl$
    CREATE FUNCTION public.crm_current_user_can_read_project_shared_attachment(p_attachment uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
    AS $body$
      SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.crm_deal_attachments attachment JOIN public.projects project ON project.deal_id=attachment.deal_id
        WHERE attachment.id=p_attachment AND attachment.is_archived=false AND attachment.visible_to_project_assignee=true
          AND auth.uid()=ANY(COALESCE(project.assigned_people,ARRAY[]::uuid[]))
      )
    $body$
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  ALTER FUNCTION public.crm_current_user_can_read_project_shared_attachment(uuid) OWNER TO postgres;
  REVOKE ALL ON FUNCTION public.crm_current_user_can_read_project_shared_attachment(uuid) FROM PUBLIC,anon,authenticated,service_role;
  GRANT EXECUTE ON FUNCTION public.crm_current_user_can_read_project_shared_attachment(uuid) TO authenticated;
  ALTER POLICY crm_project_shared_attachments_select ON public.crm_deal_attachments
    USING (public.crm_current_user_can_read_project_shared_attachment(id));
  EXECUTE replace(replace($ddl$
    CREATE FUNCTION public.crm_current_user_is_approval_assignee(p_step uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
    AS $body$
      SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.crm_deal_approval_steps step JOIN public.profiles profile ON profile.id=step.approver_id
        WHERE step.id=p_step AND step.approver_id=auth.uid() AND profile.is_active IS DISTINCT FROM false
      )
    $body$
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  ALTER FUNCTION public.crm_current_user_is_approval_assignee(uuid) OWNER TO postgres;
  REVOKE ALL ON FUNCTION public.crm_current_user_is_approval_assignee(uuid) FROM PUBLIC,anon,authenticated,service_role;
  GRANT EXECUTE ON FUNCTION public.crm_current_user_is_approval_assignee(uuid) TO authenticated;
  CREATE POLICY crm_own_approval_step_select ON public.crm_deal_approval_steps FOR SELECT TO authenticated
    USING (public.crm_current_user_is_approval_assignee(id));
  -- No caller-supplied user or deal identifier: return only currently assigned
  -- pending steps and the minimum context used by the approval list.
  EXECUTE replace(replace($ddl$
    CREATE FUNCTION public.list_my_pending_crm_approval_context() RETURNS SETOF jsonb
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
    AS $body$
      SELECT to_jsonb(step) || jsonb_build_object('deal',jsonb_build_object(
        'id',deal.id,'title',deal.title,'stage',deal.stage,'workflow_status',deal.workflow_status,
        'proposal_sent_at',deal.proposal_sent_at,
        'amount',CASE WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(deal.amount) ELSE 'null'::jsonb END,
        'crm_clients',CASE WHEN client.id IS NULL THEN NULL ELSE jsonb_build_object('name',client.name) END))
      FROM public.crm_deal_approval_steps step
      JOIN public.crm_deals deal ON deal.id=step.deal_id
      JOIN public.profiles reviewer ON reviewer.id=auth.uid() AND reviewer.is_active IS DISTINCT FROM false
      LEFT JOIN public.crm_clients client ON client.id=deal.client_id
      WHERE auth.uid() IS NOT NULL AND step.approver_id=auth.uid() AND step.status='PENDING'
        AND deal.workflow_status='PENDING_APPROVAL' AND UPPER(COALESCE(deal.stage,'')) NOT IN ('WON','LOST')
      ORDER BY step.step_order,step.created_at
    $body$
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  ALTER FUNCTION public.list_my_pending_crm_approval_context() OWNER TO postgres;
  REVOKE ALL ON FUNCTION public.list_my_pending_crm_approval_context() FROM PUBLIC,anon,authenticated,service_role;
  GRANT EXECUTE ON FUNCTION public.list_my_pending_crm_approval_context() TO authenticated,service_role;
  -- These functions add no Storage SELECT policy: an approval assignment does
  -- not itself permit issuing reusable Storage signed URLs.
  EXECUTE replace(replace($ddl$
    CREATE FUNCTION public.list_my_pending_crm_approval_documents() RETURNS SETOF jsonb
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
    AS $body$
      SELECT jsonb_build_object('id',attachment.id,'source','DEAL','deal_id',attachment.deal_id,
        'category',attachment.category,'file_name',attachment.file_name,
        'file_type',attachment.file_type,'file_size',attachment.file_size,'description',attachment.description)
      FROM public.crm_deal_attachments attachment
      JOIN public.crm_deals deal ON deal.id=attachment.deal_id
      WHERE auth.uid() IS NOT NULL AND public.can_view_business_financials(auth.uid()) AND attachment.is_archived=false
        AND attachment.file_url LIKE 'storage://crm-deal-files/%'
        AND deal.workflow_status='PENDING_APPROVAL' AND UPPER(COALESCE(deal.stage,'')) NOT IN ('WON','LOST')
        AND EXISTS (SELECT 1 FROM public.crm_deal_approval_steps step JOIN public.profiles reviewer ON reviewer.id=step.approver_id
          WHERE step.deal_id=deal.id AND step.approver_id=auth.uid() AND step.status='PENDING'
            AND reviewer.is_active IS DISTINCT FROM false)
      UNION ALL
      SELECT jsonb_build_object('id',attachment.id,'source','DESIGN','deal_id',deal.id,
        'category','DESIGN_DELIVERABLE','file_name',attachment.file_name,
        'file_type',attachment.file_type,'file_size',attachment.file_size)
      FROM public.task_attachments attachment
      JOIN public.tasks task ON task.id=attachment.task_id
      JOIN public.crm_deals deal ON deal.id=task.crm_deal_id
      WHERE auth.uid() IS NOT NULL AND public.can_view_business_financials(auth.uid())
        AND task.crm_workflow_kind='QUOTE_PROPOSAL_DESIGN' AND task.archived_at IS NULL
        AND attachment.is_archived=false AND attachment.file_url=ANY(COALESCE(task.submission_links,ARRAY[]::text[]))
        AND attachment.file_url LIKE 'storage://task-attachments/%'
        AND deal.workflow_status='PENDING_APPROVAL' AND UPPER(COALESCE(deal.stage,'')) NOT IN ('WON','LOST')
        AND EXISTS (SELECT 1 FROM public.crm_deal_approval_steps step JOIN public.profiles reviewer ON reviewer.id=step.approver_id
          WHERE step.deal_id=deal.id AND step.approver_id=auth.uid() AND step.status='PENDING'
            AND reviewer.is_active IS DISTINCT FROM false)
    $body$
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  EXECUTE replace(replace($ddl$
    CREATE FUNCTION public.get_my_pending_crm_approval_document(p_document_id uuid,p_source text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
    AS $body$
      SELECT jsonb_build_object('id',attachment.id,'source','DEAL','file_name',attachment.file_name,'file_type',attachment.file_type,
        'file_url',attachment.file_url)
      FROM public.crm_deal_attachments attachment
      JOIN public.crm_deals deal ON deal.id=attachment.deal_id
      WHERE auth.uid() IS NOT NULL AND public.can_view_business_financials(auth.uid()) AND p_source='DEAL' AND attachment.id=p_document_id AND attachment.is_archived=false
        AND attachment.file_url LIKE 'storage://crm-deal-files/%'
        AND deal.workflow_status='PENDING_APPROVAL' AND UPPER(COALESCE(deal.stage,'')) NOT IN ('WON','LOST')
        AND EXISTS (SELECT 1 FROM public.crm_deal_approval_steps step JOIN public.profiles reviewer ON reviewer.id=step.approver_id
          WHERE step.deal_id=deal.id AND step.approver_id=auth.uid() AND step.status='PENDING'
            AND reviewer.is_active IS DISTINCT FROM false)
      UNION ALL
      SELECT jsonb_build_object('id',attachment.id,'source','DESIGN','file_name',attachment.file_name,
        'file_type',attachment.file_type,'file_url',attachment.file_url)
      FROM public.task_attachments attachment
      JOIN public.tasks task ON task.id=attachment.task_id
      JOIN public.crm_deals deal ON deal.id=task.crm_deal_id
      WHERE auth.uid() IS NOT NULL AND public.can_view_business_financials(auth.uid()) AND p_source='DESIGN'
        AND attachment.id=p_document_id AND attachment.is_archived=false AND task.archived_at IS NULL
        AND task.crm_workflow_kind='QUOTE_PROPOSAL_DESIGN'
        AND attachment.file_url=ANY(COALESCE(task.submission_links,ARRAY[]::text[]))
        AND attachment.file_url LIKE 'storage://task-attachments/%'
        AND deal.workflow_status='PENDING_APPROVAL' AND UPPER(COALESCE(deal.stage,'')) NOT IN ('WON','LOST')
        AND EXISTS (SELECT 1 FROM public.crm_deal_approval_steps step JOIN public.profiles reviewer ON reviewer.id=step.approver_id
          WHERE step.deal_id=deal.id AND step.approver_id=auth.uid() AND step.status='PENDING'
            AND reviewer.is_active IS DISTINCT FROM false)
    $body$
  $ddl$, E'\r\n', E'\n'), E'\r', E'\n');
  ALTER FUNCTION public.list_my_pending_crm_approval_documents() OWNER TO postgres;
  ALTER FUNCTION public.get_my_pending_crm_approval_document(uuid,text) OWNER TO postgres;
  REVOKE ALL ON FUNCTION public.list_my_pending_crm_approval_documents(),public.get_my_pending_crm_approval_document(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
  GRANT EXECUTE ON FUNCTION public.list_my_pending_crm_approval_documents(),public.get_my_pending_crm_approval_document(uuid,text) TO authenticated,service_role;

  SELECT replace(replace(pg_get_functiondef(start_oid), E'\r\n', E'\n'), E'\r', E'\n') INTO start_def;
  original := $$IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN$$;
  replacement := $$IF UPPER(COALESCE(v_deal.stage, '')) IN ('LOST','WON') THEN$$;
  IF position(original IN start_def)=0 THEN RAISE EXCEPTION 'Start terminal-stage guard not found'; END IF;
  start_def := replace(start_def,original,replacement);
  original := '    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;';
  replacement := replace(replace($code$
    -- The existing CRM activity feed shows each previous assigned reviewer,
    -- status and reason after the current-cycle step rows are replaced.
    IF NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id=p_deal_id AND category='QUOTATION' AND NOT is_archived)
       OR NOT EXISTS (SELECT 1 FROM public.crm_deal_attachments WHERE deal_id=p_deal_id AND category='PROPOSAL' AND NOT is_archived) THEN
      RAISE EXCEPTION 'Upload the quotation and proposal before approval' USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_marketing_manager AND emp_index=3 AND is_active IS DISTINCT FROM false
                    AND (NULLIF(BTRIM(employee_id),'') IS NULL OR UPPER(BTRIM(employee_id))='MQ-03'))
       OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_general_manager AND emp_index=1 AND is_active IS DISTINCT FROM false
                    AND (NULLIF(BTRIM(employee_id),'') IS NULL OR UPPER(BTRIM(employee_id))='MQ-01'))
       OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=p_operations_manager AND emp_index=4 AND is_active IS DISTINCT FROM false
                    AND (NULLIF(BTRIM(employee_id),'') IS NULL OR UPPER(BTRIM(employee_id))='MQ-04')) THEN
      RAISE EXCEPTION 'Approval reviewers do not match the configured roles' USING ERRCODE='42501';
    END IF;
    INSERT INTO public.crm_deal_activity(deal_id,action,from_status,to_status,note,actor_id,created_at)
      SELECT step.deal_id,'APPROVAL_DECISION_HISTORY','PENDING',step.status,
        step.stage_key || ': ' || step.status || ' (' || COALESCE(NULLIF(BTRIM(reviewer.display_name),''),NULLIF(BTRIM(reviewer.full_name),''),'Unknown reviewer') || ')'
          || CASE WHEN NULLIF(BTRIM(step.decision_note),'') IS NULL THEN '' ELSE ' — ' || step.decision_note END,
        NULL,COALESCE(step.decided_at,step.created_at)
      FROM public.crm_deal_approval_steps step LEFT JOIN public.profiles reviewer ON reviewer.id=step.approver_id
      WHERE step.deal_id=p_deal_id AND step.status IN ('APPROVED','REJECTED');
    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;$code$, E'\r\n', E'\n'), E'\r', E'\n');
  IF position(original IN start_def)=0 THEN RAISE EXCEPTION 'Start history insertion point missing'; END IF;
  start_def := replace(start_def,original,replacement);
  EXECUTE start_def;

  SELECT replace(replace(pg_get_functiondef(decide_oid), E'\r\n', E'\n'), E'\r', E'\n') INTO decide_def;
  original := replace(replace($code$    SELECT * INTO v_step
      FROM public.crm_deal_approval_steps
     WHERE id = p_step_id
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;$code$, E'\r\n', E'\n'), E'\r', E'\n');
  replacement := replace(replace($code$    IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND is_active IS DISTINCT FROM false) THEN
      RAISE EXCEPTION 'Approval is unavailable' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_step FROM public.crm_deal_approval_steps WHERE id=p_step_id;
    IF NOT FOUND OR (v_step.approver_id IS DISTINCT FROM auth.uid() AND
       (NOT public.is_crm_approval_admin(auth.uid()) OR EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND (emp_index=2 OR UPPER(BTRIM(COALESCE(employee_id,'')))='MQ-02')))) THEN
      RAISE EXCEPTION 'Approval is unavailable' USING ERRCODE='42501';
    END IF;
    -- Both start and decide lock the deal before locking its approval rows.
    SELECT * INTO v_deal FROM public.crm_deals WHERE id=v_step.deal_id FOR UPDATE;
    IF NOT FOUND OR UPPER(COALESCE(v_deal.stage,'')) IN ('WON','LOST') OR v_deal.workflow_status<>'PENDING_APPROVAL' THEN
      RAISE EXCEPTION 'Approval is unavailable' USING ERRCODE='42501';
    END IF;
    SELECT * INTO v_step FROM public.crm_deal_approval_steps WHERE id=p_step_id AND deal_id=v_deal.id FOR UPDATE;
    IF NOT FOUND OR (v_step.approver_id IS DISTINCT FROM auth.uid() AND
       (NOT public.is_crm_approval_admin(auth.uid()) OR EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND (emp_index=2 OR UPPER(BTRIM(COALESCE(employee_id,'')))='MQ-02')))) THEN
      RAISE EXCEPTION 'Approval is unavailable' USING ERRCODE='42501';
    END IF;$code$, E'\r\n', E'\n'), E'\r', E'\n');
  IF position(original IN decide_def)=0 THEN RAISE EXCEPTION 'Decision lock or authorization insertion point missing'; END IF;
  decide_def := replace(decide_def,original,replacement);
  EXECUTE decide_def;
  REVOKE ALL ON FUNCTION public.start_deal_approval(uuid,uuid,uuid,uuid),public.decide_deal_approval(uuid,text,text) FROM PUBLIC,anon;
  GRANT EXECUTE ON FUNCTION public.start_deal_approval(uuid,uuid,uuid,uuid),public.decide_deal_approval(uuid,text,text) TO authenticated,service_role;
  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('public.start_deal_approval(uuid,uuid,uuid,uuid)','6ad663afc289e5e28d04e15581160f05',true),
      ('public.decide_deal_approval(uuid,text,text)','497827d94d1debbad4d20fac851e782d',true),
      ('public.crm_current_user_is_approval_assignee(uuid)','5a0038c6809bb93fcaa0989c02e30fa2',false),
      ('public.list_my_pending_crm_approval_context()','966d8606e8be30a7b9429dd291e448d7',true),
      ('public.list_my_pending_crm_approval_documents()','df69bad234c8e1a4f96b0921569dd379',true),
      ('public.get_my_pending_crm_approval_document(uuid,text)','a4827f5e03ce30ba48276ff6ef6005ad',true)
    ) AS required(signature,fingerprint,service_execute)
    LEFT JOIN pg_proc p ON p.oid=to_regprocedure(required.signature)
    WHERE p.oid IS NULL OR md5(pg_get_functiondef(p.oid))<>required.fingerprint
      OR p.proowner<>'postgres'::regrole OR NOT p.prosecdef
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, pg_temp']::text[]
      OR has_function_privilege('anon',p.oid,'execute')
      OR NOT has_function_privilege('authenticated',p.oid,'execute')
      OR has_function_privilege('service_role',p.oid,'execute') IS DISTINCT FROM required.service_execute
  ) THEN RAISE EXCEPTION 'Approval function postcondition failed (decision %, list %, document %)',md5(pg_get_functiondef(decide_oid)),md5(pg_get_functiondef('public.list_my_pending_crm_approval_documents()'::regprocedure)),md5(pg_get_functiondef('public.get_my_pending_crm_approval_document(uuid,text)'::regprocedure)); END IF;
  -- Pin the caller-bound helpers and generated Design creator after the
  -- replacements; abort the entire migration if a postcondition differs.
  IF EXISTS (
    SELECT 1 FROM (VALUES
      ('public.create_crm_design_task_for_deal(uuid)','de121607ac05add508f99f071f22c01e',NOT staging_case,true),
      ('public.can_read_crm_deal_file(text,uuid)','59a03bfe102fa169718a67d5d9072b76',true,true),
      ('public.decide_crm_design_task_approval(uuid,text,text)','8b08289b008d1305180e30ce8de2af37',true,true),
      ('public.crm_current_user_can_read_project_shared_attachment(uuid)','86e1a9ea6b2dda7d2f5b4b3950a4692f',true,false)
    ) AS required(signature,fingerprint,auth_execute,service_execute)
    LEFT JOIN pg_proc p ON p.oid=to_regprocedure(required.signature)
    WHERE p.oid IS NULL OR md5(pg_get_functiondef(p.oid))<>required.fingerprint
      OR p.proowner<>'postgres'::regrole OR NOT p.prosecdef
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public, pg_temp']::text[]
      OR has_function_privilege('anon',p.oid,'execute')
      OR has_function_privilege('authenticated',p.oid,'execute') IS DISTINCT FROM required.auth_execute
      OR has_function_privilege('service_role',p.oid,'execute') IS DISTINCT FROM required.service_execute
  ) OR (NOT staging_case AND NOT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_trigger t ON t.tgfoid=p.oid
      WHERE p.oid=to_regprocedure('public.guard_crm_design_task_identity()')
        AND md5(pg_get_functiondef(p.oid))='5c3ead4a8fd56bb7fcdd9dc9f91f102e'
        AND p.proowner='postgres'::regrole AND p.prosecdef
        AND p.proconfig=ARRAY['search_path=public, pg_temp']::text[]
        AND NOT has_function_privilege('anon',p.oid,'execute')
        AND NOT has_function_privilege('authenticated',p.oid,'execute')
        AND NOT has_function_privilege('service_role',p.oid,'execute')
        AND t.tgrelid='public.tasks'::regclass AND t.tgname='crm_design_identity_guard' AND t.tgenabled='O'
  )) THEN RAISE EXCEPTION 'Design or attachment helper postcondition failed'; END IF;
END;
$migration$;
COMMIT;
