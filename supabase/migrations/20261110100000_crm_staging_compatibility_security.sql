-- Narrow compatibility/security correction for the verified 2026-11-09
-- Staging catalog. Apply only after CRM 20261109100000 and MQ-20 20261109110000.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

-- Staging's reviewed employee-access RPC bodies require authenticated
-- callers, but the fresh catalog shows explicit PUBLIC and anon EXECUTE ACLs.
-- Correct only those two exact, fingerprint-pinned RPCs before the general
-- caller scan below. The enclosing transaction rolls this correction back if
-- any later preflight check fails. Authenticated/service_role access remains.
DO $employee_access_acl$
DECLARE
  v_oid oid;
BEGIN
  FOREACH v_oid IN ARRAY ARRAY[
    to_regprocedure('public.get_task_employee_access_grants()'),
    to_regprocedure('public.set_task_employee_access_grant(uuid,uuid,boolean)')
  ]::oid[] LOOP
    IF v_oid IS NULL
       OR (v_oid = to_regprocedure('public.get_task_employee_access_grants()')
           AND md5(pg_get_functiondef(v_oid)) <> '5f058c8d26e4c59aa2276d3935381bb4')
       OR (v_oid = to_regprocedure('public.set_task_employee_access_grant(uuid,uuid,boolean)')
           AND md5(pg_get_functiondef(v_oid)) <> '739e91d6a1fcba734b5e98846b1d0779')
       OR NOT EXISTS (
         SELECT 1
         FROM pg_proc routine
         WHERE routine.oid = v_oid
           AND routine.proowner = 'postgres'::regrole
           AND routine.prosecdef
           AND 'search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[]))
       )
       OR NOT has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'Employee task-access RPC fingerprint, owner, security, or authenticated grant differs from the reviewed Staging definition';
    END IF;

    IF v_oid = to_regprocedure('public.get_task_employee_access_grants()') THEN
      EXECUTE 'REVOKE ALL ON FUNCTION public.get_task_employee_access_grants() FROM PUBLIC, anon';
    ELSE
      EXECUTE 'REVOKE ALL ON FUNCTION public.set_task_employee_access_grant(uuid, uuid, boolean) FROM PUBLIC, anon';
    END IF;

    IF has_function_privilege('anon', v_oid, 'EXECUTE')
       OR NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
       OR EXISTS (
         SELECT 1
         FROM aclexplode((SELECT routine.proacl FROM pg_proc routine WHERE routine.oid = v_oid)) acl
         WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
       ) THEN
      RAISE EXCEPTION 'Employee task-access RPC ACL correction did not preserve authenticated access while removing PUBLIC/anon execution';
    END IF;
  END LOOP;
END;
$employee_access_acl$;

DO $preflight$
DECLARE
  v_oid oid;
  v_mq20_profile_source text;
  v_attachment_manage_source text;
  v_attachment_read_source text;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'CRM compatibility migration must be run as postgres';
  END IF;

  -- These fingerprints bind the compatibility edits to the exact Staging
  -- definitions reviewed on 2026-11-09. Drift stops the migration for review.
  IF to_regprocedure('public.enforce_deal_workflow_transition()') IS NULL
     OR md5(pg_get_functiondef(to_regprocedure('public.enforce_deal_workflow_transition()'))) <> 'd7a69cae93a7ca717e766b853a940b82'
     OR to_regprocedure('public.can_view_own_crm_contact_task(uuid,uuid)') IS NULL
     OR md5(pg_get_functiondef(to_regprocedure('public.can_view_own_crm_contact_task(uuid,uuid)'))) <> 'ec2fc0ab26cc97d2cfce2509b2e20bc8'
     OR to_regprocedure('public.crm_is_own_generated_contact_task(uuid,uuid)') IS NULL
     OR md5(pg_get_functiondef(to_regprocedure('public.crm_is_own_generated_contact_task(uuid,uuid)'))) <> '3fa1d8615f9d9222519ef50757abdb0b'
     OR to_regprocedure('public.decide_crm_design_task_approval(uuid,text,text)') IS NULL
     OR md5(pg_get_functiondef(to_regprocedure('public.decide_crm_design_task_approval(uuid,text,text)'))) <> '2ff4140400da5c8afe992409ab714eba'
     OR to_regprocedure('public.queue_task_notification(uuid,uuid,text,text)') IS NULL
     OR md5(pg_get_functiondef(to_regprocedure('public.queue_task_notification(uuid,uuid,text,text)'))) <> '1cf17344666c71d4ec9acf22280554ef' THEN
    RAISE EXCEPTION 'A reviewed Staging function definition has drifted; stop and re-review before applying compatibility changes';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger trigger_row
    WHERE trigger_row.tgrelid = 'public.crm_deals'::regclass
      AND trigger_row.tgname = 'crm_deal_workflow_transition'
      AND trigger_row.tgfoid = 'public.enforce_deal_workflow_transition()'::regprocedure
      AND trigger_row.tgenabled = 'O'
  ) THEN
    RAISE EXCEPTION 'Expected enabled CRM workflow trigger is missing or changed';
  END IF;

  IF to_regprocedure('public.guard_crm_contact_discussion_task()') IS NULL
     OR to_regprocedure('public.sync_crm_contact_discussion_assignees()') IS NULL
     OR to_regprocedure('public.execute_crm_contact_discussion_task(uuid,text,text,text)') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger trigger_row
        WHERE trigger_row.tgrelid = 'public.tasks'::regclass
          AND trigger_row.tgname = 'crm_contact_discussion_task_guard'
          AND trigger_row.tgenabled = 'O'
          AND trigger_row.tgfoid = 'public.guard_crm_contact_discussion_task()'::regprocedure
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger trigger_row
        WHERE trigger_row.tgrelid = 'public.crm_deals'::regclass
          AND trigger_row.tgname = 'crm_sync_contact_discussion_assignees'
          AND trigger_row.tgenabled = 'O'
          AND trigger_row.tgfoid = 'public.sync_crm_contact_discussion_assignees()'::regprocedure
     ) THEN
    RAISE EXCEPTION 'CRM and MQ-20 migrations must be applied first with their Contact-task identity and assignment guards enabled';
  END IF;

  SELECT routine.oid INTO v_oid
    FROM pg_proc routine
   WHERE routine.oid = 'public.queue_task_notification(uuid,uuid,text,text)'::regprocedure
     AND routine.prosecdef
     AND routine.proowner = 'postgres'::regrole
     AND 'search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[]));
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'Notification RPC ownership or SECURITY DEFINER configuration has drifted';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc routine
      JOIN pg_roles owner_role ON owner_role.oid = routine.proowner
     WHERE routine.oid IN (
       'public.can_view_own_crm_contact_task(uuid,uuid)'::regprocedure,
       'public.crm_is_own_generated_contact_task(uuid,uuid)'::regprocedure,
       'public.decide_crm_design_task_approval(uuid,text,text)'::regprocedure
     )
       AND (owner_role.rolname <> 'postgres'
         OR NOT routine.prosecdef
         OR NOT ('search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[]))))
  ) OR EXISTS (
    SELECT 1
      FROM pg_proc routine
      JOIN pg_roles owner_role ON owner_role.oid = routine.proowner
     WHERE routine.oid = 'public.enforce_deal_workflow_transition()'::regprocedure
       AND (owner_role.rolname <> 'postgres'
         OR routine.prosecdef
         OR NOT ('search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[]))))
  ) THEN
    RAISE EXCEPTION 'A reviewed function owner, security mode, or search_path has drifted';
  END IF;

  SELECT regexp_replace(lower(routine.prosrc), '[[:space:]]+', '', 'g')
    INTO v_mq20_profile_source
    FROM pg_proc routine
    JOIN pg_roles owner_role ON owner_role.oid = routine.proowner
   WHERE routine.oid = to_regprocedure('public.is_mq20_profile(uuid)')
     AND owner_role.rolname = 'postgres'
     AND routine.prosecdef
     AND 'search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[]));
  IF v_mq20_profile_source IS NULL
     OR md5(pg_get_functiondef(to_regprocedure('public.is_mq20_profile(uuid)'))) <> '873a1aecadf1d0fec3fceca822adf6b7'
     OR position('profile.id=p_user_id' IN v_mq20_profile_source) = 0
     OR position('upper(btrim(coalesce(profile.employee_id,' IN v_mq20_profile_source) = 0
     OR position('mq-20' IN v_mq20_profile_source) = 0
     OR position('profile.is_activeisdistinctfromfalse' IN v_mq20_profile_source) = 0 THEN
    RAISE EXCEPTION 'MQ-20 authorization helper no longer enforces the reviewed active employee identity';
  END IF;

  -- Preserve the exact 13 restrictive Staging policies while changing only
  -- the helper call that currently accepts an arbitrary profile UUID.
  IF (SELECT count(*) FROM pg_policies
       WHERE schemaname='public'
         AND policyname IN (
           'mq20_only_ines_task_attachments_select',
           'mq20_no_task_comments_delete','mq20_no_task_comments_insert',
           'mq20_no_task_comments_update','mq20_only_ines_task_comments_select',
           'mq20_no_task_lists_delete','mq20_no_task_lists_insert',
           'mq20_no_task_lists_update','mq20_only_ines_task_lists_select',
           'mq20_no_tasks_delete','mq20_no_tasks_insert','mq20_no_tasks_update',
           'mq20_only_ines_tasks_select'
         )) <> 13
     OR EXISTS (
       SELECT 1
       FROM (VALUES
         ('mq20_only_ines_task_attachments_select','task_attachments','SELECT'),
         ('mq20_no_task_comments_delete','task_comments','DELETE'),
         ('mq20_no_task_comments_insert','task_comments','INSERT'),
         ('mq20_no_task_comments_update','task_comments','UPDATE'),
         ('mq20_only_ines_task_comments_select','task_comments','SELECT'),
         ('mq20_no_task_lists_delete','task_lists','DELETE'),
         ('mq20_no_task_lists_insert','task_lists','INSERT'),
         ('mq20_no_task_lists_update','task_lists','UPDATE'),
         ('mq20_only_ines_task_lists_select','task_lists','SELECT'),
         ('mq20_no_tasks_delete','tasks','DELETE'),
         ('mq20_no_tasks_insert','tasks','INSERT'),
         ('mq20_no_tasks_update','tasks','UPDATE'),
         ('mq20_only_ines_tasks_select','tasks','SELECT')
       ) AS expected(policy_name, table_name, command_name)
       LEFT JOIN pg_policies actual
         ON actual.schemaname='public'
        AND actual.policyname=expected.policy_name
        AND actual.tablename=expected.table_name
        AND actual.cmd=expected.command_name
        AND actual.permissive='RESTRICTIVE'
        AND actual.roles=ARRAY['authenticated']::name[]
       WHERE actual.policyname IS NULL
          OR NOT (COALESCE(actual.qual,'') || COALESCE(actual.with_check,''))
                 ~* 'is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]*\)'
     ) THEN
    RAISE EXCEPTION 'MQ-20 policy inventory or helper expressions have drifted; stop before changing policy authorization';
  END IF;

  -- Do not leave another RLS policy calling the UUID-taking helper directly.
  IF EXISTS (
    SELECT 1 FROM pg_policies policy_row
     WHERE policy_row.schemaname='public'
       AND (COALESCE(policy_row.qual,'') || COALESCE(policy_row.with_check,'')) ~* 'is_mq20_profile[[:space:]]*\('
       AND policy_row.policyname NOT IN (
         'mq20_only_ines_task_attachments_select',
         'mq20_no_task_comments_delete','mq20_no_task_comments_insert',
         'mq20_no_task_comments_update','mq20_only_ines_task_comments_select',
         'mq20_no_task_lists_delete','mq20_no_task_lists_insert',
         'mq20_no_task_lists_update','mq20_only_ines_task_lists_select',
         'mq20_no_tasks_delete','mq20_no_tasks_insert','mq20_no_tasks_update',
         'mq20_only_ines_tasks_select'
       )
  ) THEN
    RAISE EXCEPTION 'An unreviewed RLS policy still calls the UUID-taking MQ-20 helper';
  END IF;

  -- Internal helper callers must remain trusted postgres-owned definers. Any
  -- caller exposed to authenticated users must be a known self-scoped task RPC
  -- or the Marketing Manager-only grant RPCs whose authorization is checked
  -- inside the function before membership-based decisions are returned/made.
  IF EXISTS (
    SELECT 1
      FROM pg_proc caller
      JOIN pg_namespace namespace ON namespace.oid=caller.pronamespace
      JOIN pg_roles owner_role ON owner_role.oid=caller.proowner
     WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
       AND caller.oid <> to_regprocedure('public.is_mq20_profile(uuid)')
       AND caller.prosrc ILIKE '%is_mq20_profile%'
       AND (owner_role.rolname <> 'postgres' OR NOT caller.prosecdef
         OR NOT (
           'search_path=public, pg_temp' = ANY(COALESCE(caller.proconfig, ARRAY[]::text[]))
           OR 'search_path=pg_catalog, public, hrsys_private' = ANY(COALESCE(caller.proconfig, ARRAY[]::text[]))
         ))
  ) THEN
    RAISE EXCEPTION 'An MQ-20 helper caller is not a postgres-owned SECURITY DEFINER with a fixed search_path';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc caller
      JOIN pg_namespace namespace ON namespace.oid=caller.pronamespace
     WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
       AND caller.oid <> to_regprocedure('public.is_mq20_profile(uuid)')
       AND caller.prosrc ILIKE '%is_mq20_profile%'
       AND has_function_privilege('anon', caller.oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'An anonymous-executable RPC can reach the MQ-20 membership helper';
  END IF;

  -- These two live Staging attachment helpers are authenticated-executable
  -- SECURITY DEFINER callers. Permit them only at the reviewed fingerprints
  -- and only while they bind authenticated user IDs to auth.uid(). The
  -- fingerprint checks also pin the attachment/task/project authorization
  -- predicates to the exact Staging definitions reviewed on 2026-11-10.
  SELECT regexp_replace(lower(routine.prosrc), '[[:space:]]+', '', 'g')
    INTO v_attachment_manage_source
    FROM pg_proc routine
    JOIN pg_roles owner_role ON owner_role.oid = routine.proowner
   WHERE routine.oid = to_regprocedure('public.can_manage_task_attachments(uuid,uuid)')
     AND owner_role.rolname = 'postgres'
     AND routine.prosecdef
     AND 'search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[]));

  SELECT regexp_replace(lower(routine.prosrc), '[[:space:]]+', '', 'g')
    INTO v_attachment_read_source
    FROM pg_proc routine
    JOIN pg_roles owner_role ON owner_role.oid = routine.proowner
   WHERE routine.oid = to_regprocedure('public.can_read_task_attachment_file(text,uuid)')
     AND owner_role.rolname = 'postgres'
     AND routine.prosecdef
     AND 'search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[]));

  IF v_attachment_manage_source IS NULL
     OR md5(pg_get_functiondef(to_regprocedure('public.can_manage_task_attachments(uuid,uuid)'))) <> '6f6e252dcf1908ef50c33e7c1048a50f'
     OR position('(auth.uid()isnullorp_user_id=auth.uid())' IN v_attachment_manage_source) = 0
     OR position('(auth.uid()isnullornotpublic.is_mq20_profile(auth.uid()))' IN v_attachment_manage_source) = 0
     OR has_function_privilege('anon', 'public.can_manage_task_attachments(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.can_manage_task_attachments(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.can_manage_task_attachments(uuid,uuid)', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM aclexplode((SELECT routine.proacl FROM pg_proc routine WHERE routine.oid = 'public.can_manage_task_attachments(uuid,uuid)'::regprocedure)) acl
        WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Task attachment management helper fingerprint or caller scoping has drifted';
  END IF;

  IF v_attachment_read_source IS NULL
     OR md5(pg_get_functiondef(to_regprocedure('public.can_read_task_attachment_file(text,uuid)'))) <> 'd0bbd53cff17e3914bf912b7e590b565'
     OR position('ifp_user_idisnullor(auth.uid()isnotnullandp_user_id<>auth.uid())thenreturnfalse;endif;' IN v_attachment_read_source) = 0
     OR position('(auth.uid()isnullornotpublic.is_mq20_profile(auth.uid()))' IN v_attachment_read_source) = 0
     OR has_function_privilege('anon', 'public.can_read_task_attachment_file(text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.can_read_task_attachment_file(text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.can_read_task_attachment_file(text,uuid)', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM aclexplode((SELECT routine.proacl FROM pg_proc routine WHERE routine.oid = 'public.can_read_task_attachment_file(text,uuid)'::regprocedure)) acl
        WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Task attachment reader helper fingerprint or caller scoping has drifted';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc caller
      JOIN pg_namespace namespace ON namespace.oid=caller.pronamespace
     WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
       AND caller.oid <> to_regprocedure('public.is_mq20_profile(uuid)')
       AND caller.prosrc ILIKE '%is_mq20_profile%'
       AND has_function_privilege('authenticated', caller.oid, 'EXECUTE')
       AND NOT EXISTS (
         SELECT 1 FROM unnest(ARRAY[
           to_regprocedure('public.can_access_task(uuid,uuid)'),
           to_regprocedure('public.can_manage_task(uuid,uuid)'),
           to_regprocedure('public.can_view_own_crm_contact_task(uuid,uuid)'),
           to_regprocedure('public.crm_is_own_generated_contact_task(uuid,uuid)'),
           to_regprocedure('public.execute_crm_contact_discussion_task(uuid,text,text,text)'),
           to_regprocedure('public.can_manage_task_attachments(uuid,uuid)'),
           to_regprocedure('public.can_read_task_attachment_file(text,uuid)'),
           to_regprocedure('public.get_task_employee_access_grants()'),
           to_regprocedure('public.set_task_employee_access_grant(uuid,uuid,boolean)')
         ]::oid[]) expected(oid)
         WHERE expected.oid IS NOT NULL AND expected.oid=caller.oid
       )
  ) THEN
    RAISE EXCEPTION 'An unreviewed authenticated RPC can reach the MQ-20 membership helper';
  END IF;

  IF to_regprocedure('public.execute_crm_contact_discussion_task(uuid,text,text,text)') IS NOT NULL
     AND (SELECT prosrc !~* 'auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]+IS[[:space:]]+NULL[[:space:]]+OR[[:space:]]+NOT[[:space:]]+public\.is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\('
            FROM pg_proc WHERE oid='public.execute_crm_contact_discussion_task(uuid,text,text,text)'::regprocedure) THEN
    RAISE EXCEPTION 'Scoped MQ-20 execution RPC no longer binds membership to auth.uid()';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc caller
      JOIN pg_namespace namespace ON namespace.oid=caller.pronamespace
     WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
       AND caller.prosrc ILIKE '%is_mq20_profile%'
       AND caller.oid IN (
         to_regprocedure('public.can_access_task(uuid,uuid)'),
         to_regprocedure('public.can_manage_task(uuid,uuid)'),
         to_regprocedure('public.can_view_own_crm_contact_task(uuid,uuid)'),
         to_regprocedure('public.crm_is_own_generated_contact_task(uuid,uuid)')
       )
       AND caller.prosrc !~* 'p_user_id[[:space:]]*=[[:space:]]*auth\.uid\s*\('
  ) THEN
    RAISE EXCEPTION 'A current-user task access RPC no longer scopes its supplied user id to auth.uid()';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc caller
      JOIN pg_namespace namespace ON namespace.oid=caller.pronamespace
     WHERE namespace.nspname NOT IN ('pg_catalog','information_schema')
       AND caller.oid IN (
         to_regprocedure('public.get_task_employee_access_grants()'),
         to_regprocedure('public.set_task_employee_access_grant(uuid,uuid,boolean)')
       )
       AND caller.prosrc !~* 'is_marketing_task_manager[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\('
  ) THEN
    RAISE EXCEPTION 'Task grant RPC no longer requires the authorized Marketing Manager context';
  END IF;
  -- Every tracked database function that calls the privileged queue must run
  -- as the trusted postgres definer. Service-role direct execution is retained.
  IF EXISTS (
    SELECT 1
      FROM pg_proc caller
      JOIN pg_namespace namespace ON namespace.oid = caller.pronamespace
     WHERE namespace.nspname NOT IN ('pg_catalog', 'information_schema')
       AND caller.oid <> 'public.queue_task_notification(uuid,uuid,text,text)'::regprocedure
       AND caller.prosrc ILIKE '%queue_task_notification%'
       AND (NOT caller.prosecdef OR caller.proowner <> 'postgres'::regrole)
  ) THEN
    RAISE EXCEPTION 'A notification queue caller is not a postgres-owned SECURITY DEFINER function; review before revoking client execution';
  END IF;

  IF to_regclass('public.crm_generated_tasks') IS NULL
     OR to_regclass('public.crm_deals') IS NULL
     OR to_regclass('public.tasks') IS NULL
     OR to_regclass('public.profiles') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.crm_deals'::regclass AND attname='assignee_ids' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass AND attname='archived_at' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass AND attname='assignee_ids' AND NOT attisdropped)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.tasks'::regclass AND attname='visible_to' AND NOT attisdropped) THEN
    RAISE EXCEPTION 'Required CRM Contact-task access schema is missing';
  END IF;
END;
$preflight$;

-- RLS policies receive only a no-argument current-user check. Internal
-- postgres-owned SECURITY DEFINER functions retain access to the UUID helper
-- for trusted checks such as the assignment-grant RPC.
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

DO $mq20_policy_rewrite$
DECLARE
  policy_row record;
  rewritten text;
  policy_count integer := 0;
BEGIN
  FOR policy_row IN
    SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
      FROM pg_policies
     WHERE schemaname='public'
       AND policyname IN (
         'mq20_only_ines_task_attachments_select',
         'mq20_no_task_comments_delete','mq20_no_task_comments_insert',
         'mq20_no_task_comments_update','mq20_only_ines_task_comments_select',
         'mq20_no_task_lists_delete','mq20_no_task_lists_insert',
         'mq20_no_task_lists_update','mq20_only_ines_task_lists_select',
         'mq20_no_tasks_delete','mq20_no_tasks_insert','mq20_no_tasks_update',
         'mq20_only_ines_tasks_select'
       )
  LOOP
    IF policy_row.permissive <> 'RESTRICTIVE'
       OR policy_row.roles <> ARRAY['authenticated']::name[]
       OR (COALESCE(policy_row.qual,'') || COALESCE(policy_row.with_check,''))
           !~* 'is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]*\)' THEN
      RAISE EXCEPTION 'MQ-20 policy % changed after preflight; refusing rewrite', policy_row.policyname;
    END IF;

    IF policy_row.qual IS NOT NULL THEN
      rewritten := regexp_replace(
        policy_row.qual,
        '(public\.)?is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]*\)',
        'public.is_mq20_current_user()', 'gi'
      );
      IF rewritten = policy_row.qual THEN
        RAISE EXCEPTION 'MQ-20 policy % qualification was not rewritten', policy_row.policyname;
      END IF;
      EXECUTE format('ALTER POLICY %I ON %I.%I USING (%s)',
                     policy_row.policyname, policy_row.schemaname, policy_row.tablename, rewritten);
    END IF;

    IF policy_row.with_check IS NOT NULL THEN
      rewritten := regexp_replace(
        policy_row.with_check,
        '(public\.)?is_mq20_profile[[:space:]]*\([[:space:]]*auth\.uid[[:space:]]*\([[:space:]]*\)[[:space:]]*\)',
        'public.is_mq20_current_user()', 'gi'
      );
      IF rewritten = policy_row.with_check THEN
        RAISE EXCEPTION 'MQ-20 policy % check expression was not rewritten', policy_row.policyname;
      END IF;
      EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (%s)',
                     policy_row.policyname, policy_row.schemaname, policy_row.tablename, rewritten);
    END IF;
    policy_count := policy_count + 1;
  END LOOP;

  IF policy_count <> 13 OR EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname='public'
       AND policyname IN (
         'mq20_only_ines_task_attachments_select',
         'mq20_no_task_comments_delete','mq20_no_task_comments_insert',
         'mq20_no_task_comments_update','mq20_only_ines_task_comments_select',
         'mq20_no_task_lists_delete','mq20_no_task_lists_insert',
         'mq20_no_task_lists_update','mq20_only_ines_task_lists_select',
         'mq20_no_tasks_delete','mq20_no_tasks_insert','mq20_no_tasks_update',
         'mq20_only_ines_tasks_select'
       )
       AND ((COALESCE(qual,'') || COALESCE(with_check,'')) ~* 'is_mq20_profile[[:space:]]*\('
         OR (COALESCE(qual,'') || COALESCE(with_check,'')) !~* 'is_mq20_current_user[[:space:]]*\(')
  ) THEN
    RAISE EXCEPTION 'MQ-20 policies were not fully converted to the current-user-only helper';
  END IF;
END;
$mq20_policy_rewrite$;

REVOKE ALL ON FUNCTION public.is_mq20_profile(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_mq20_profile(uuid) TO service_role;
DO $mq20_acl_postcheck$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM pg_proc routine
      CROSS JOIN LATERAL aclexplode(COALESCE(routine.proacl, acldefault('f', routine.proowner))) AS privilege
     WHERE routine.oid = 'public.is_mq20_profile(uuid)'::regprocedure
       AND privilege.grantee = 0
       AND privilege.privilege_type = 'EXECUTE'
  ) OR has_function_privilege('anon', 'public.is_mq20_profile(uuid)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.is_mq20_profile(uuid)', 'EXECUTE')
    OR NOT has_function_privilege('postgres', 'public.is_mq20_profile(uuid)', 'EXECUTE')
    OR has_function_privilege('anon', 'public.is_mq20_current_user()', 'EXECUTE')
    OR NOT has_function_privilege('authenticated', 'public.is_mq20_current_user()', 'EXECUTE')
    OR NOT has_function_privilege('service_role', 'public.is_mq20_profile(uuid)', 'EXECUTE')
    OR has_function_privilege('service_role', 'public.is_mq20_current_user()', 'EXECUTE') THEN
    RAISE EXCEPTION 'MQ-20 helper grants do not enforce the caller-scoped authorization boundary';
  END IF;
END;
$mq20_acl_postcheck$;

-- Preserve the Staging workflow function and its Lost-reason rule while
-- removing only the obsolete rejection of the distinct NEGOTIATION stage.
CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF NEW.stage = 'LOST' AND NULLIF(BTRIM(COALESCE(NEW.lost_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A lost reason is required' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;
ALTER FUNCTION public.enforce_deal_workflow_transition() OWNER TO postgres;

-- Grant a direct authenticated call to the existing approval RPC only after
-- its existing approver/admin authorization has been fingerprint-verified.
REVOKE ALL ON FUNCTION public.decide_crm_design_task_approval(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_crm_design_task_approval(uuid, text, text) TO authenticated;

-- Current deal assignees (including secondary assignees) may read only the
-- exact active, registry-backed Contact Discussion task assigned to that set.
-- The current deal row is the source of truth, so reassignment revokes access
-- immediately even if a task assignment ever becomes inconsistent.
CREATE OR REPLACE FUNCTION public.crm_is_own_generated_contact_task(p_task_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  SELECT p_task_id IS NOT NULL
    AND p_user_id IS NOT NULL
    AND p_user_id = auth.uid()
    AND public.is_mq20_profile(p_user_id)
    AND EXISTS (
      SELECT 1
        FROM public.crm_generated_tasks generated
        JOIN public.tasks task
          ON task.id = generated.task_id
         AND task.crm_deal_id = generated.deal_id
        JOIN public.crm_deals deal ON deal.id = generated.deal_id
        JOIN public.profiles employee
          ON employee.id = p_user_id
         AND employee.is_active IS DISTINCT FROM false
        CROSS JOIN LATERAL (
          SELECT COALESCE(
            NULLIF(deal.assignee_ids, '{}'::uuid[]),
            CASE WHEN deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[deal.assigned_to]::uuid[] END
          ) AS current_assignees
        ) assignment
       WHERE generated.task_id = p_task_id
         AND generated.kind = 'CONTACT_DISCUSSION'
         AND task.crm_workflow_kind = 'CONTACT_DISCUSSION'
         AND task.archived_at IS NULL
         AND UPPER(COALESCE(deal.stage, '')) <> 'LOST'
         AND p_user_id = ANY(assignment.current_assignees)
         AND task.assignee_id IS NOT DISTINCT FROM assignment.current_assignees[1]
         AND COALESCE(task.assignee_ids, '{}'::uuid[]) IS NOT DISTINCT FROM assignment.current_assignees
         AND COALESCE(task.visible_to, '{}'::uuid[]) IS NOT DISTINCT FROM assignment.current_assignees
    );
$function$;
ALTER FUNCTION public.crm_is_own_generated_contact_task(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.crm_is_own_generated_contact_task(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_is_own_generated_contact_task(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_view_own_crm_contact_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
  SELECT p_task_id IS NOT NULL
     AND p_user_id IS NOT NULL
     AND p_user_id = auth.uid()
     AND public.is_mq20_profile(p_user_id)
     AND public.crm_is_own_generated_contact_task(p_task_id, p_user_id)
     AND public.can_access_task(p_task_id, p_user_id);
$function$;
ALTER FUNCTION public.can_view_own_crm_contact_task(uuid, uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.can_view_own_crm_contact_task(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_own_crm_contact_task(uuid, uuid) TO authenticated, service_role;

-- Trigger and SECURITY DEFINER callers continue to run as their postgres
-- owner. Untrusted PostgREST roles lose direct invocation of the privileged
-- notification writer; the trusted service role remains explicitly allowed.
REVOKE ALL ON FUNCTION public.queue_task_notification(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.queue_task_notification(uuid, uuid, text, text) TO service_role;

DO $postcheck$
BEGIN
  IF has_function_privilege('anon', 'public.queue_task_notification(uuid,uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.queue_task_notification(uuid,uuid,text,text)', 'EXECUTE')
     OR EXISTS (
       SELECT 1
         FROM aclexplode((SELECT routine.proacl FROM pg_proc routine WHERE routine.oid='public.queue_task_notification(uuid,uuid,text,text)'::regprocedure)) acl
        WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
     )
     OR NOT has_function_privilege('service_role', 'public.queue_task_notification(uuid,uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.decide_crm_design_task_approval(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.decide_crm_design_task_approval(uuid,text,text)', 'EXECUTE')
     OR EXISTS (
       SELECT 1
         FROM aclexplode((SELECT routine.proacl FROM pg_proc routine WHERE routine.oid='public.decide_crm_design_task_approval(uuid,text,text)'::regprocedure)) acl
        WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE'
     )
     OR NOT has_function_privilege('authenticated', 'public.can_view_own_crm_contact_task(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.crm_is_own_generated_contact_task(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.can_view_own_crm_contact_task(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.crm_is_own_generated_contact_task(uuid,uuid)', 'EXECUTE')
     OR EXISTS (
       SELECT 1
         FROM pg_proc routine
         JOIN pg_roles owner_role ON owner_role.oid = routine.proowner
        WHERE routine.oid IN (
          'public.can_view_own_crm_contact_task(uuid,uuid)'::regprocedure,
          'public.crm_is_own_generated_contact_task(uuid,uuid)'::regprocedure,
          'public.enforce_deal_workflow_transition()'::regprocedure,
          'public.decide_crm_design_task_approval(uuid,text,text)'::regprocedure
        )
          AND owner_role.rolname <> 'postgres'
     ) THEN
    RAISE EXCEPTION 'Compatibility migration permission postcheck failed';
  END IF;
END;
$postcheck$;

NOTIFY pgrst, 'reload schema';
COMMIT;
