-- Production-only CRM/MQ-20 security compatibility migration.
-- Depends on 20261112100000 (Contact task identity/CRM assignment foundation)
-- and 20261112110000 (scoped MQ-20 execution boundary).
-- Does not modify Staging's approved migration files or Production's existing
-- CRM transition, Design approval, Lost-deal, Task Manager, or notification code.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

DO $production_security_preflight$
BEGIN
  IF current_user <> 'postgres' OR current_database() <> 'postgres'
     OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999 THEN
    RAISE EXCEPTION 'Production CRM security compatibility requires PostgreSQL 17.x, database postgres, role postgres';
  END IF;
  IF to_regclass('public.crm_generated_tasks') IS NULL
     OR to_regclass('public.crm_deals') IS NULL
     OR to_regclass('public.tasks') IS NULL
     OR to_regnamespace('hrsys_private') IS NULL
     OR to_regprocedure('public.guard_crm_contact_discussion_task()') IS NULL
     OR to_regprocedure('public.enforce_mq20_task_service_boundaries()') IS NULL
     OR to_regprocedure('public.execute_crm_contact_discussion_task(uuid,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Production CRM and MQ-20 foundation migrations are not fully installed';
  END IF;
  IF to_regprocedure('public.crm_is_own_generated_contact_task(uuid,uuid)') IS NULL
     OR (SELECT prosecdef FROM pg_proc WHERE oid='public.crm_is_own_generated_contact_task(uuid,uuid)'::regprocedure) IS DISTINCT FROM true
     OR (SELECT proowner FROM pg_proc WHERE oid='public.crm_is_own_generated_contact_task(uuid,uuid)'::regprocedure) <> 'postgres'::regrole THEN
    RAISE EXCEPTION 'Caller-scoped generated Contact-task reader is missing or misconfigured';
  END IF;
  IF to_regprocedure('public.is_mq20_current_user()') IS NOT NULL THEN
    RAISE EXCEPTION 'The current-user MQ-20 wrapper already exists; inspect partial application';
  END IF;
  IF md5(pg_get_functiondef('public.is_mq20_profile(uuid)'::regprocedure)) <> '873a1aecadf1d0fec3fceca822adf6b7'
     OR md5(pg_get_functiondef('public.get_task_employee_access_grants()'::regprocedure)) <> '5f058c8d26e4c59aa2276d3935381bb4'
     OR md5(pg_get_functiondef('public.set_task_employee_access_grant(uuid,uuid,boolean)'::regprocedure)) <> '739e91d6a1fcba734b5e98846b1d0779'
     OR md5(pg_get_functiondef('public.can_manage_task_attachments(uuid,uuid)'::regprocedure)) <> '05cee3a9820835715f0ed5e4de774070'
     OR md5(pg_get_functiondef('public.can_read_task_attachment_file(text,uuid)'::regprocedure)) <> '3eb91925c2deabb14b39df97367b8492' THEN
    RAISE EXCEPTION 'Production MQ-20, employee-access, or attachment-helper definitions drifted from the reviewed baseline';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc routine
    WHERE routine.oid IN (
      'public.is_mq20_profile(uuid)'::regprocedure,
      'public.get_task_employee_access_grants()'::regprocedure,
      'public.set_task_employee_access_grant(uuid,uuid,boolean)'::regprocedure,
      'public.can_manage_task_attachments(uuid,uuid)'::regprocedure,
      'public.can_read_task_attachment_file(text,uuid)'::regprocedure
    ) AND (routine.proowner <> 'postgres'::regrole OR NOT routine.prosecdef
      OR NOT ('search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[]))))
  ) THEN
    RAISE EXCEPTION 'A reviewed Production SECURITY DEFINER owner or search_path changed';
  END IF;
  IF NOT has_function_privilege('authenticated','public.is_mq20_profile(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.is_mq20_profile(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.can_manage_task_attachments(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.can_manage_task_attachments(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.can_read_task_attachment_file(text,uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.can_read_task_attachment_file(text,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.get_task_employee_access_grants()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.set_task_employee_access_grant(uuid,uuid,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'Production helper/RPC effective grants differ from the reviewed pre-migration baseline';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'mq20_%') <> 12
     OR EXISTS (
       SELECT 1 FROM (VALUES
         ('task_comments','mq20_no_task_comments_delete','DELETE','e0c5f7bdff96fa1477c3e0e38e596c1c'),
         ('task_comments','mq20_no_task_comments_insert','INSERT','49e6dd8168f7a15e2173fc1d11ba52d4'),
         ('task_comments','mq20_no_task_comments_update','UPDATE','a0c3496abd09d8fd5eaed346d91f80e0'),
         ('task_comments','mq20_only_ines_task_comments_select','SELECT','55626ddd4795af2cd5fbc4d3cd80f764'),
         ('task_lists','mq20_no_task_lists_delete','DELETE','e0c5f7bdff96fa1477c3e0e38e596c1c'),
         ('task_lists','mq20_no_task_lists_insert','INSERT','49e6dd8168f7a15e2173fc1d11ba52d4'),
         ('task_lists','mq20_no_task_lists_update','UPDATE','a0c3496abd09d8fd5eaed346d91f80e0'),
         ('task_lists','mq20_only_ines_task_lists_select','SELECT','7a7a4d4f564758b6214f017faed7bfde'),
         ('tasks','mq20_no_tasks_delete','DELETE','e0c5f7bdff96fa1477c3e0e38e596c1c'),
         ('tasks','mq20_no_tasks_insert','INSERT','49e6dd8168f7a15e2173fc1d11ba52d4'),
         ('tasks','mq20_no_tasks_update','UPDATE','a0c3496abd09d8fd5eaed346d91f80e0'),
         ('tasks','mq20_only_ines_tasks_select','SELECT','4fabb76daca5d65ca54656782bb8286e')
       ) expected(tablename, policyname, cmd, expression_md5)
       LEFT JOIN pg_policies actual
         ON actual.schemaname='public' AND actual.tablename=expected.tablename
        AND actual.policyname=expected.policyname AND actual.cmd=expected.cmd
        AND actual.permissive='RESTRICTIVE' AND actual.roles=ARRAY['authenticated']::name[]
       WHERE actual.policyname IS NULL
          OR md5(COALESCE(actual.qual,'') || '|' || COALESCE(actual.with_check,'')) <> expected.expression_md5
          OR (COALESCE(actual.qual,'') || COALESCE(actual.with_check,''))
             !~* 'is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]*\)'
     ) THEN
    RAISE EXCEPTION 'Production 12-policy MQ-20 baseline differs from the reviewed expressions; refusing policy rewrite';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies policy_row
     WHERE policy_row.schemaname='public'
       AND policy_row.policyname NOT LIKE 'mq20_%'
       AND (COALESCE(policy_row.qual,'') || COALESCE(policy_row.with_check,'')) ~* 'is_mq20_profile[[:space:]]*\('
  ) THEN
    RAISE EXCEPTION 'An unreviewed Production RLS policy calls the arbitrary-UUID MQ-20 helper';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgname='crm_deals_enforce_workflow_transition' AND tgenabled='O' AND tgfoid='public.enforce_deal_workflow_transition()'::regprocedure)
     OR md5(pg_get_functiondef('public.enforce_deal_workflow_transition()'::regprocedure)) <> '600cb3b42c794a4bac4a9e8796327b8e'
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgname='protect_lost_crm_deal_edits_trigger' AND tgenabled='O')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass AND tgname='crm_design_task_completion_trigger' AND tgenabled='O')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.tasks'::regclass AND tgname='crm_design_task_status_update_trigger' AND tgenabled='O') THEN
    RAISE EXCEPTION 'Production Negotiation/Lost/Design workflow protections drifted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc caller
    JOIN pg_namespace namespace ON namespace.oid=caller.pronamespace
    WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
      AND caller.oid <> 'public.is_mq20_profile(uuid)'::regprocedure
      AND caller.prosrc ILIKE '%is_mq20_profile%'
      AND (caller.proowner <> 'postgres'::regrole OR NOT caller.prosecdef
        OR CASE
          WHEN caller.oid IN (
            'public.get_task_employee_access_grants()'::regprocedure,
            'public.set_task_employee_access_grant(uuid,uuid,boolean)'::regprocedure,
            'public.enforce_mq20_task_service_boundaries()'::regprocedure,
            'public.execute_crm_contact_discussion_task(uuid,text,text,text)'::regprocedure
          ) THEN NOT ('search_path=public, pg_temp'=ANY(COALESCE(caller.proconfig,ARRAY[]::text[])))
          WHEN caller.oid = 'hrsys_private.valid_mq20_task_context(uuid,text,text)'::regprocedure
            THEN NOT ('search_path=pg_catalog, public, hrsys_private'=ANY(COALESCE(caller.proconfig,ARRAY[]::text[])))
          ELSE true
        END)
  ) THEN
    RAISE EXCEPTION 'A Production MQ-20 helper caller is not a trusted postgres SECURITY DEFINER';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc caller
     WHERE caller.prosrc ILIKE '%is_mq20_profile%'
       AND caller.oid <> 'public.is_mq20_profile(uuid)'::regprocedure
       AND caller.oid NOT IN (
         'public.get_task_employee_access_grants()'::regprocedure,
         'public.set_task_employee_access_grant(uuid,uuid,boolean)'::regprocedure,
         'public.enforce_mq20_task_service_boundaries()'::regprocedure,
         'public.execute_crm_contact_discussion_task(uuid,text,text,text)'::regprocedure,
         'hrsys_private.valid_mq20_task_context(uuid,text,text)'::regprocedure
       )
  ) THEN
    RAISE EXCEPTION 'Unreviewed Production function calls is_mq20_profile; inspect caller and authorization before revoking client EXECUTE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc caller
     WHERE caller.prosrc ILIKE '%is_mq20_profile%'
       AND caller.oid <> 'public.is_mq20_profile(uuid)'::regprocedure
       AND has_function_privilege('anon', caller.oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'An anonymous-executable Production caller can reach the MQ-20 membership helper';
  END IF;
  IF has_function_privilege('anon','public.get_task_employee_access_grants()','EXECUTE')
     OR has_function_privilege('anon','public.set_task_employee_access_grant(uuid,uuid,boolean)','EXECUTE')
     OR md5(pg_get_functiondef('public.can_access_task(uuid,uuid)'::regprocedure)) <> 'cf2adeb248ea95c4f56d88f40e015347' THEN
    RAISE EXCEPTION 'An employee-access grant or task-access caller differs from the reviewed Production baseline';
  END IF;
END;
$production_security_preflight$;

-- RLS policies receive only a no-argument caller-scoped membership check.
-- Trusted SECURITY DEFINER server functions retain the UUID helper, while a
-- client cannot probe arbitrary profile UUIDs directly.
CREATE OR REPLACE FUNCTION public.is_mq20_current_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  SELECT auth.uid() IS NOT NULL AND public.is_mq20_profile(auth.uid());
$function$;
ALTER FUNCTION public.is_mq20_current_user() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.is_mq20_current_user() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.is_mq20_current_user() TO authenticated;

DO $production_policy_rewrite$
DECLARE
  policy_row record;
  rewritten text;
  processed integer := 0;
BEGIN
  FOR policy_row IN
    SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
      FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'mq20_%'
  LOOP
    IF policy_row.permissive <> 'RESTRICTIVE'
       OR policy_row.roles <> ARRAY['authenticated']::name[]
       OR (COALESCE(policy_row.qual,'') || COALESCE(policy_row.with_check,''))
          !~* 'is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]*\)' THEN
      RAISE EXCEPTION 'Production MQ-20 policy % changed after preflight', policy_row.policyname;
    END IF;
    IF policy_row.qual IS NOT NULL THEN
      rewritten := regexp_replace(policy_row.qual,
        '(public\.)?is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]*\)',
        'public.is_mq20_current_user()', 'gi');
      IF policy_row.policyname='mq20_only_ines_tasks_select' THEN
        rewritten := '(' || rewritten || ') OR public.crm_is_own_generated_contact_task(id, auth.uid())';
      ELSIF policy_row.policyname='mq20_only_ines_task_comments_select' THEN
        rewritten := '(' || rewritten || ') OR public.crm_is_own_generated_contact_task(task_id, auth.uid())';
      END IF;
      IF rewritten=policy_row.qual THEN RAISE EXCEPTION 'Policy % USING expression did not change', policy_row.policyname; END IF;
      EXECUTE format('ALTER POLICY %I ON %I.%I USING (%s)', policy_row.policyname, policy_row.schemaname, policy_row.tablename, rewritten);
    END IF;
    IF policy_row.with_check IS NOT NULL THEN
      rewritten := regexp_replace(policy_row.with_check,
        '(public\.)?is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]*\)',
        'public.is_mq20_current_user()', 'gi');
      IF rewritten=policy_row.with_check THEN RAISE EXCEPTION 'Policy % WITH CHECK expression did not change', policy_row.policyname; END IF;
      EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (%s)', policy_row.policyname, policy_row.schemaname, policy_row.tablename, rewritten);
    END IF;
    processed := processed + 1;
  END LOOP;
  IF processed <> 12 THEN RAISE EXCEPTION 'Expected exactly 12 Production MQ-20 policies, found %', processed; END IF;
END;
$production_policy_rewrite$;

-- Production had no MQ-20 attachment SELECT restriction. Add the missing
-- fail-closed boundary: preserve ordinary users, existing Ines access, and
-- only the current active CRM assignees for registered Contact attachments.
CREATE POLICY mq20_only_ines_task_attachments_select
ON public.task_attachments AS RESTRICTIVE FOR SELECT TO authenticated
USING ((NOT public.is_mq20_current_user())
  OR public.is_ines_modani_task(task_id)
  OR public.crm_is_own_generated_contact_task(task_id, auth.uid()));

-- Direct UUID probing is closed for clients. The employee-access RPCs remain
-- callable only by authenticated users and service_role; their exact reviewed
-- bodies retain Marketing Manager authorization and can call the helper as
-- postgres-owned SECURITY DEFINER routines.
REVOKE ALL ON FUNCTION public.is_mq20_profile(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_mq20_profile(uuid) TO service_role;

-- Preserve the existing helper call graph and service-side use while binding
-- user-supplied IDs to the authenticated caller whenever a JWT is present.
CREATE OR REPLACE FUNCTION public.can_manage_task_attachments(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  SELECT p_user_id IS NOT NULL
    AND (auth.uid() IS NULL OR p_user_id = auth.uid())
    AND (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
    AND EXISTS (
      SELECT 1 FROM public.tasks task
      LEFT JOIN public.projects project ON project.id = task.project_id
      WHERE task.id = p_task_id
        AND (task.created_by = p_user_id OR task.assignee_id = p_user_id
          OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
          OR task.supervisor_id = p_user_id OR project.created_by = p_user_id
          OR project.project_manager_id = p_user_id
          OR public.is_project_portfolio_admin(p_user_id))
    );
$function$;
ALTER FUNCTION public.can_manage_task_attachments(uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.can_manage_task_attachments(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_task_attachments(uuid,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_read_task_attachment_file(p_object_name text, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF p_user_id IS NULL OR (auth.uid() IS NOT NULL AND p_user_id <> auth.uid()) THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.task_attachments attachment
    JOIN public.tasks task ON task.id = attachment.task_id
    LEFT JOIN public.projects project ON project.id = task.project_id
    WHERE attachment.file_url = 'storage://task-attachments/' || p_object_name
      AND (public.can_access_task(task.id, p_user_id)
        OR ((auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
          AND project.id IS NOT NULL
          AND p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::uuid[]))))
  );
END;
$function$;
ALTER FUNCTION public.can_read_task_attachment_file(text,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.can_read_task_attachment_file(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_task_attachment_file(text,uuid) TO authenticated, service_role;

DO $production_security_postcheck$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc routine CROSS JOIN LATERAL aclexplode(COALESCE(routine.proacl, acldefault('f', routine.proowner))) acl WHERE routine.oid='public.is_mq20_profile(uuid)'::regprocedure AND acl.grantee=0 AND acl.privilege_type='EXECUTE')
     OR has_function_privilege('anon','public.is_mq20_profile(uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.is_mq20_profile(uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.is_mq20_profile(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.is_mq20_current_user()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.is_mq20_current_user()','EXECUTE')
     OR has_function_privilege('service_role','public.is_mq20_current_user()','EXECUTE') THEN
    RAISE EXCEPTION 'Production MQ-20 helper grants do not enforce current-user-only access';
  END IF;
  IF has_function_privilege('anon','public.can_manage_task_attachments(uuid,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.can_read_task_attachment_file(text,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.can_manage_task_attachments(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.can_read_task_attachment_file(text,uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.can_manage_task_attachments(uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.can_read_task_attachment_file(text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Production attachment helper grants changed unexpectedly';
  END IF;
  IF md5(pg_get_functiondef('public.can_access_task(uuid,uuid)'::regprocedure)) <> 'cf2adeb248ea95c4f56d88f40e015347'
     OR md5(pg_get_functiondef('public.can_manage_task(uuid,uuid)'::regprocedure)) <> '86544056ca930279dffb1835a9480e62'
     OR (SELECT proowner FROM pg_proc WHERE oid='public.can_access_task(uuid,uuid)'::regprocedure) <> 'postgres'::regrole
     OR (SELECT prosecdef FROM pg_proc WHERE oid='public.can_access_task(uuid,uuid)'::regprocedure) IS DISTINCT FROM true
     OR (SELECT proowner FROM pg_proc WHERE oid='public.can_manage_task(uuid,uuid)'::regprocedure) <> 'postgres'::regrole
     OR (SELECT prosecdef FROM pg_proc WHERE oid='public.can_manage_task(uuid,uuid)'::regprocedure) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Production Task Manager authorization helper definitions drifted';
  END IF;
  IF position('p_user_id=auth.uid()' IN regexp_replace(lower(pg_get_functiondef('public.can_manage_task_attachments(uuid,uuid)'::regprocedure)), '[[:space:]]+', '', 'g')) = 0
     OR position('p_user_id<>auth.uid()' IN regexp_replace(lower(pg_get_functiondef('public.can_read_task_attachment_file(text,uuid)'::regprocedure)), '[[:space:]]+', '', 'g')) = 0 THEN
    RAISE EXCEPTION 'Production attachment helpers are not bound to auth.uid() after replacement';
  END IF;
  IF (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'mq20_%') <> 13
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'mq20_%'
       AND ((COALESCE(qual,'') || COALESCE(with_check,'')) ~* 'is_mq20_profile[[:space:]]*\('
         OR (COALESCE(qual,'') || COALESCE(with_check,'')) !~* 'is_mq20_current_user[[:space:]]*\(')) THEN
    RAISE EXCEPTION 'Production MQ-20 policy set is incomplete or still calls the UUID-probing helper';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='task_attachments' AND policyname='mq20_only_ines_task_attachments_select'
      AND permissive='RESTRICTIVE' AND roles=ARRAY['authenticated']::name[] AND cmd='SELECT'
      AND qual ILIKE '%crm_is_own_generated_contact_task%'
  ) OR NOT has_function_privilege('authenticated','public.crm_is_own_generated_contact_task(uuid,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.crm_is_own_generated_contact_task(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Production MQ-20 attachment restriction or Contact reader grants are incorrect';
  END IF;
  IF md5(pg_get_functiondef('public.enforce_deal_workflow_transition()'::regprocedure)) <> '600cb3b42c794a4bac4a9e8796327b8e'
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgname='crm_deals_enforce_workflow_transition' AND tgenabled='O')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.crm_deals'::regclass AND tgname='protect_lost_crm_deal_edits_trigger' AND tgenabled='O') THEN
    RAISE EXCEPTION 'Production CRM Negotiation/Lost workflow protection changed';
  END IF;
  IF NOT has_function_privilege('authenticated','public.get_task_employee_access_grants()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.set_task_employee_access_grant(uuid,uuid,boolean)','EXECUTE')
     OR has_function_privilege('anon','public.get_task_employee_access_grants()','EXECUTE')
     OR has_function_privilege('anon','public.set_task_employee_access_grant(uuid,uuid,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'Marketing Manager employee-access RPC grants changed';
  END IF;
END;
$production_security_postcheck$;

COMMIT;
