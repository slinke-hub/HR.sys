-- MQ-20 may execute only an actively assigned, registry-backed CRM Contact
-- Discussion task through this narrowly scoped RPC. Direct task/child writes,
-- general task permissions, notifications, and successor workflows stay closed.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
BEGIN
  IF current_user <> 'postgres' OR current_database() <> 'postgres'
     OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999 THEN
    RAISE EXCEPTION 'MQ-20 Contact Discussion migration requires PostgreSQL 17.x, database postgres, role postgres';
  END IF;
  IF to_regnamespace('hrsys_private') IS NOT NULL THEN
    RAISE EXCEPTION 'Private MQ-20 context schema already exists; inspect before retrying';
  END IF;
  IF to_regclass('public.crm_generated_tasks') IS NULL
     OR to_regclass('public.crm_deals') IS NULL
     OR to_regclass('public.tasks') IS NULL
     OR to_regclass('public.profiles') IS NULL
     OR to_regclass('public.task_waiting_history') IS NULL
     OR to_regclass('public.task_blocker_history') IS NULL
     OR to_regclass('public.task_activity') IS NULL THEN
    RAISE EXCEPTION 'Required CRM/task relations are missing; apply the approved CRM and productivity migrations first';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_attribute
     WHERE attrelid = 'public.crm_deals'::regclass AND attname = 'assignee_ids' AND NOT attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_attribute
     WHERE attrelid = 'public.tasks'::regclass AND attname = 'archived_at' AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'CRM multi-assignee or archived-task schema is missing';
  END IF;
  IF to_regprocedure('public.protect_task_access_fields()') IS NULL
     OR to_regprocedure('public.notify_task_change()') IS NULL
     OR to_regprocedure('public.queue_task_status_notification()') IS NULL
     OR to_regprocedure('public.record_task_activity()') IS NULL
     OR to_regprocedure('public.is_mq20_profile(uuid)') IS NULL
     OR to_regprocedure('public.is_mq07_design_list(uuid,uuid)') IS NULL
     OR to_regprocedure('public.can_access_crm(uuid)') IS NULL
     OR to_regprocedure('public.productivity_validate_category(text,boolean)') IS NULL
     OR to_regprocedure('public.task_dependency_blocked(uuid)') IS NULL
     OR to_regprocedure('public.record_task_activity()') IS NULL THEN
    RAISE EXCEPTION 'Required verified MQ-20, task, or productivity functions are missing';
  END IF;
  IF md5(pg_get_functiondef('public.is_mq20_profile(uuid)'::regprocedure)) <> '873a1aecadf1d0fec3fceca822adf6b7'
     OR md5(pg_get_functiondef('public.protect_task_access_fields()'::regprocedure)) <> '37bccb413df3d923abb1359d26163835'
     OR md5(pg_get_functiondef('public.notify_task_change()'::regprocedure)) <> 'ebc537e75039c00b111c2f49cd035264'
     OR md5(pg_get_functiondef('public.queue_task_status_notification()'::regprocedure)) <> 'bc564a2ba87f4fb0069166f1ab8e9117'
     OR md5(pg_get_functiondef('public.productivity_validate_category(text,boolean)'::regprocedure)) <> 'e2ac5f19260639580db7a9114b8e99f7'
     OR md5(pg_get_functiondef('public.task_dependency_blocked(uuid)'::regprocedure)) <> 'aa88c0617de92d64c9ce981c10800d45'
     OR md5(pg_get_functiondef('public.record_task_activity()'::regprocedure)) <> 'd557158db68567ee570ddd667865d797' THEN
    RAISE EXCEPTION 'Production MQ-20 authorization, task-access, or notification function baseline drifted';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM (VALUES
        ('crm_deals','id'), ('crm_deals','stage'), ('crm_deals','assigned_to'), ('crm_deals','assignee_ids'),
        ('profiles','id'), ('profiles','is_active'),
        ('tasks','id'), ('tasks','title'), ('tasks','created_by'), ('tasks','assignee_id'), ('tasks','assignee_ids'),
        ('tasks','visible_to'), ('tasks','supervisor_id'), ('tasks','project_id'), ('tasks','parent_task_id'),
        ('tasks','visibility'), ('tasks','watchers'), ('tasks','task_list_id'), ('tasks','crm_deal_id'),
        ('tasks','crm_workflow_kind'), ('tasks','archived_at'), ('tasks','status'), ('tasks','started_at'),
        ('tasks','completed_at'), ('tasks','work_state'), ('tasks','resume_status'), ('tasks','waiting_category'),
        ('tasks','waiting_related_user_id'), ('tasks','waiting_note'), ('tasks','waiting_since'),
        ('tasks','blocked_category'), ('tasks','blocked_related_user_id'), ('tasks','blocked_note'),
        ('tasks','blocked_since'), ('tasks','updated_at'),
        ('task_waiting_history','task_id'), ('task_waiting_history','actor_id'), ('task_waiting_history','category'),
        ('task_waiting_history','related_user_id'), ('task_waiting_history','note'), ('task_waiting_history','started_at'),
        ('task_waiting_history','resumed_at'), ('task_waiting_history','resumed_by'),
        ('task_blocker_history','task_id'), ('task_blocker_history','actor_id'), ('task_blocker_history','category'),
        ('task_blocker_history','related_user_id'), ('task_blocker_history','note'), ('task_blocker_history','created_at'),
        ('task_blocker_history','resolved_at'), ('task_blocker_history','resolved_by'),
        ('task_activity','task_id'), ('task_activity','actor_id'), ('task_activity','action'),
        ('task_activity','from_status'), ('task_activity','to_status'), ('task_activity','metadata')
      ) AS required(relation_name, column_name)
     WHERE NOT EXISTS (
       SELECT 1 FROM pg_attribute attribute
        WHERE attribute.attrelid = to_regclass('public.' || required.relation_name)
          AND attribute.attname = required.column_name
          AND NOT attribute.attisdropped
     )
  ) THEN
    RAISE EXCEPTION 'Required task, assignment, or productivity columns are missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_attribute attribute
     WHERE attribute.attrelid IN ('public.crm_deals'::regclass, 'public.tasks'::regclass)
       AND attribute.attname = 'assignee_ids'
       AND NOT attribute.attisdropped
       AND attribute.atttypid <> 'uuid[]'::regtype
  ) OR EXISTS (
    SELECT 1 FROM pg_attribute attribute
     WHERE attribute.attrelid = 'public.tasks'::regclass
       AND attribute.attname = 'visible_to'
       AND NOT attribute.attisdropped
       AND attribute.atttypid <> 'uuid[]'::regtype
  ) THEN
    RAISE EXCEPTION 'CRM/task assignee and visibility columns must remain uuid[]';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM unnest(ARRAY[
        'public.protect_task_access_fields()'::regprocedure,
        'public.notify_task_change()'::regprocedure,
        'public.queue_task_status_notification()'::regprocedure,
        'public.sync_crm_deal_assignees()'::regprocedure,
        'public.task_dependency_blocked(uuid)'::regprocedure,
        'public.record_task_activity()'::regprocedure
      ]) AS expected(function_oid)
      JOIN pg_proc routine ON routine.oid = expected.function_oid
      JOIN pg_roles owner_role ON owner_role.oid = routine.proowner
     WHERE owner_role.rolname <> 'postgres'
        OR NOT routine.prosecdef
        OR NOT ('search_path=public, pg_temp' = ANY(COALESCE(routine.proconfig, ARRAY[]::text[])))
  ) THEN
    RAISE EXCEPTION 'A required trigger function owner or SECURITY DEFINER search_path has drifted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_trigger trg
    WHERE trg.tgrelid = 'public.tasks'::regclass AND trg.tgname = 'mq20_task_service_view_only'
  ) OR to_regprocedure('public.enforce_mq20_task_service_boundaries()') IS NOT NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger trg
       WHERE trg.tgrelid = 'public.tasks'::regclass
         AND trg.tgname = 'crm_contact_discussion_task_guard'
         AND trg.tgenabled = 'O'
         AND trg.tgfoid = 'public.guard_crm_contact_discussion_task()'::regprocedure
     )
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger trg
       WHERE trg.tgrelid = 'public.tasks'::regclass
         AND trg.tgname = 'protect_task_access_fields_trigger'
         AND trg.tgenabled = 'O'
         AND trg.tgfoid = 'public.protect_task_access_fields()'::regprocedure
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_trigger trg
       WHERE trg.tgrelid = 'public.tasks'::regclass
         AND trg.tgname = 'notify_task_change_trigger'
         AND trg.tgenabled = 'O'
         AND trg.tgfoid = 'public.notify_task_change()'::regprocedure
     ) OR NOT EXISTS (
       SELECT 1 FROM pg_trigger trg
       WHERE trg.tgrelid = 'public.tasks'::regclass
         AND trg.tgname = 'task_status_notification_trigger'
         AND trg.tgenabled = 'O'
         AND trg.tgfoid = 'public.queue_task_status_notification()'::regprocedure
     ) THEN
    RAISE EXCEPTION 'Production Contact guard or task security/notification trigger baseline drifted';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger trg
    WHERE trg.tgrelid = 'public.crm_deals'::regclass
      AND trg.tgname = 'crm_deal_assignees_sync'
      AND trg.tgenabled = 'O'
      AND trg.tgfoid = 'public.sync_crm_deal_assignees()'::regprocedure
  ) THEN
    RAISE EXCEPTION 'CRM assignee normalization trigger is missing or changed; apply the approved CRM migration first';
  END IF;
  IF (SELECT count(*) FROM pg_trigger trg
      WHERE trg.tgfoid = 'public.record_task_activity()'::regprocedure
        AND NOT trg.tgisinternal) <> 3
     OR EXISTS (
       SELECT 1 FROM pg_trigger trg
       WHERE trg.tgfoid = 'public.record_task_activity()'::regprocedure
         AND NOT trg.tgisinternal
         AND (trg.tgrelid <> 'public.tasks'::regclass OR trg.tgenabled <> 'O'
           OR trg.tgname NOT IN ('task_activity_after_insert','task_activity_after_update','task_activity_before_delete'))
     ) THEN
    RAISE EXCEPTION 'Production task-activity trigger attachments differ from the reviewed baseline';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_trigger trg
    WHERE trg.tgrelid = 'public.crm_deals'::regclass
      AND trg.tgname = 'crm_sync_contact_discussion_assignees'
  ) THEN
    RAISE EXCEPTION 'Contact Discussion assignment-sync trigger already exists; inspect before retrying';
  END IF;
  IF to_regprocedure('public.execute_crm_contact_discussion_task(uuid,text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'The scoped MQ-20 execution RPC already exists; inspect before retrying';
  END IF;
END;
$preflight$;

-- SECURITY DEFINER trigger routines must not be attachable to caller-owned
-- temporary tables. Keep the existing public.tasks behavior, but scope the
-- routine to its reviewed table and make its execution privilege internal.
CREATE OR REPLACE FUNCTION public.record_task_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF TG_TABLE_SCHEMA IS DISTINCT FROM 'public' OR TG_TABLE_NAME IS DISTINCT FROM 'tasks' THEN
    RAISE EXCEPTION 'Task activity may only be recorded by the public.tasks triggers'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
    VALUES (NEW.id, auth.uid(), 'TASK_CREATED', '{}'::jsonb);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      INSERT INTO public.task_activity(task_id, actor_id, action, from_status, to_status)
      VALUES (NEW.id, auth.uid(), 'TASK_STATUS_CHANGED', OLD.status, NEW.status);
    END IF;
    IF NEW.assignee_id IS DISTINCT FROM OLD.assignee_id OR NEW.assignee_ids IS DISTINCT FROM OLD.assignee_ids THEN
      INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
      VALUES (NEW.id, auth.uid(), 'TASK_ASSIGNED',
        jsonb_build_object('assignee_id', NEW.assignee_id, 'assignee_ids', NEW.assignee_ids));
    END IF;
    RETURN NEW;
  ELSE
    INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
    VALUES (OLD.id, auth.uid(), 'TASK_DELETED', jsonb_build_object('title', OLD.title));
    RETURN OLD;
  END IF;
END;
$function$;
ALTER FUNCTION public.record_task_activity() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.record_task_activity() FROM PUBLIC, anon, authenticated, service_role;
DO $activity_guard_postcheck$
BEGIN
  IF md5(pg_get_functiondef('public.record_task_activity()'::regprocedure)) <> '564aa16803893f7f33c867444367f2ae'
     OR (SELECT proowner FROM pg_proc WHERE oid='public.record_task_activity()'::regprocedure) <> 'postgres'::regrole
     OR (SELECT prosecdef FROM pg_proc WHERE oid='public.record_task_activity()'::regprocedure) IS DISTINCT FROM true
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.record_task_activity()'::regprocedure
       AND 'search_path=public, pg_temp'=ANY(COALESCE(proconfig,ARRAY[]::text[])))
     OR has_function_privilege('anon','public.record_task_activity()','EXECUTE')
     OR has_function_privilege('authenticated','public.record_task_activity()','EXECUTE')
     OR has_function_privilege('service_role','public.record_task_activity()','EXECUTE') THEN
    RAISE EXCEPTION 'Task activity trigger function boundary was not hardened as expected';
  END IF;
END;
$activity_guard_postcheck$;

CREATE SCHEMA hrsys_private;
ALTER SCHEMA hrsys_private OWNER TO postgres;
REVOKE ALL ON SCHEMA hrsys_private FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE hrsys_private.mq20_task_write_context (
  token uuid PRIMARY KEY,
  backend_pid integer NOT NULL,
  transaction_id bigint NOT NULL,
  actor_id uuid,
  task_id uuid NOT NULL,
  deal_id uuid NOT NULL,
  purpose text NOT NULL CHECK (purpose IN ('EXECUTION', 'ASSIGN_SYNC')),
  action text NOT NULL,
  expected_assignees uuid[] NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE hrsys_private.mq20_task_write_context OWNER TO postgres;
ALTER TABLE hrsys_private.mq20_task_write_context ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE hrsys_private.mq20_task_write_context FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION hrsys_private.valid_mq20_task_context(
  p_task_id uuid,
  p_purpose text,
  p_action text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, hrsys_private
AS $function$
DECLARE
  v_token uuid;
  v_context hrsys_private.mq20_task_write_context%ROWTYPE;
  v_task public.tasks%ROWTYPE;
  v_deal public.crm_deals%ROWTYPE;
  v_assignees uuid[];
BEGIN
  BEGIN
    v_token := NULLIF(current_setting('app.hrsys_mq20_task_context', true), '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN false;
  END;
  IF v_token IS NULL THEN RETURN false; END IF;

  SELECT * INTO v_context
    FROM hrsys_private.mq20_task_write_context
   WHERE token = v_token
     AND backend_pid = pg_backend_pid()
     AND transaction_id = txid_current()
     AND actor_id IS NOT DISTINCT FROM auth.uid()
     AND task_id = p_task_id
     AND purpose = p_purpose
     AND (p_action IS NULL OR action = p_action);
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id;
  IF NOT FOUND OR v_task.archived_at IS NOT NULL
     OR v_task.task_list_id IS NOT NULL
     OR v_task.crm_deal_id IS DISTINCT FROM v_context.deal_id
     OR v_task.crm_workflow_kind IS DISTINCT FROM 'CONTACT_DISCUSSION'
     OR NOT EXISTS (
       SELECT 1 FROM public.crm_generated_tasks mapping
        WHERE mapping.deal_id = v_context.deal_id
          AND mapping.task_id = p_task_id
          AND mapping.kind = 'CONTACT_DISCUSSION'
     ) THEN
    RETURN false;
  END IF;

  SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_context.deal_id;
  IF NOT FOUND OR UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN RETURN false; END IF;
  v_assignees := COALESCE(
    NULLIF(v_deal.assignee_ids, '{}'::uuid[]),
    CASE WHEN v_deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[v_deal.assigned_to]::uuid[] END
  );
  IF cardinality(v_assignees) = 0
     OR v_assignees IS DISTINCT FROM v_context.expected_assignees
     OR EXISTS (
       SELECT 1 FROM unnest(v_assignees) AS selected(id)
        WHERE NOT EXISTS (
          SELECT 1 FROM public.profiles profile
           WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false
        )
     ) THEN
    RETURN false;
  END IF;

  IF p_purpose = 'EXECUTION' THEN
    RETURN public.is_mq20_profile(auth.uid())
       AND auth.uid() = ANY(v_assignees)
       AND COALESCE(NULLIF(v_task.assignee_ids, '{}'::uuid[]), ARRAY[v_task.assignee_id]::uuid[]) = v_assignees
       AND v_task.assignee_id = v_assignees[1];
  END IF;

  RETURN p_purpose = 'ASSIGN_SYNC'
     AND (auth.uid() IS NULL OR public.can_access_crm(auth.uid()));
END;
$function$;
ALTER FUNCTION hrsys_private.valid_mq20_task_context(uuid, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.valid_mq20_task_context(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION hrsys_private.is_mq20_notification_suppressed(p_task_id uuid)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, hrsys_private
AS $function$
  SELECT hrsys_private.valid_mq20_task_context(p_task_id, 'EXECUTION', NULL)
      OR hrsys_private.valid_mq20_task_context(p_task_id, 'ASSIGN_SYNC', NULL)
$function$;
ALTER FUNCTION hrsys_private.is_mq20_notification_suppressed(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION hrsys_private.is_mq20_notification_suppressed(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- Extend only the verified view-only guard. Existing Contact-task INSERT
-- exception and all comment/attachment/dependency/DELETE denials are retained.
CREATE OR REPLACE FUNCTION public.enforce_mq20_task_service_boundaries()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  v_action text;
  v_changed jsonb;
  v_allowed text[];
BEGIN
  IF caller_id IS NULL OR NOT public.is_mq20_profile(caller_id) THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'tasks' THEN
    IF TG_OP = 'INSERT'
       AND NEW.created_by = caller_id
       AND NEW.assignee_id = caller_id
       AND caller_id = ANY(COALESCE(NEW.assignee_ids, '{}'::uuid[]))
       AND NEW.crm_workflow_kind = 'CONTACT_DISCUSSION'
       AND EXISTS (
         SELECT 1 FROM public.crm_generated_tasks generated
          WHERE generated.task_id = NEW.id
            AND generated.deal_id = NEW.crm_deal_id
            AND generated.kind = 'CONTACT_DISCUSSION'
       ) THEN
      RETURN NEW;
    END IF;

    -- A CRM-authorized stage change may be performed by an MQ-20 employee
    -- other than the selected deal assignee. Permit only the Contact task
    -- created by M1's scoped transaction context, after M1's alphabetically
    -- earlier task identity guard registered the exact id/deal/kind tuple.
    -- A client-set GUC alone is insufficient: the registry is postgres-only,
    -- and every assignment, active-profile, stage, creator, and CRM-access
    -- predicate is rechecked here.
    IF TG_OP = 'INSERT'
       AND current_setting('app.crm_contact_discussion_creation', true) = 'on'
       AND NEW.created_by = caller_id
       AND caller_id IS NOT NULL
       AND COALESCE(public.can_access_crm(caller_id), false)
       AND NEW.crm_workflow_kind = 'CONTACT_DISCUSSION'
       AND NEW.task_list_id IS NULL
       AND NEW.notify_via_email IS DISTINCT FROM true
       AND EXISTS (
         SELECT 1
           FROM public.crm_deals deal
          WHERE deal.id = NEW.crm_deal_id
            AND UPPER(COALESCE(deal.stage,'')) = 'QUALIFICATION'
            AND NEW.assignee_id = (COALESCE(NULLIF(deal.assignee_ids, '{}'::uuid[]),
                  CASE WHEN deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[deal.assigned_to]::uuid[] END))[1]
            AND NEW.assignee_ids = COALESCE(NULLIF(deal.assignee_ids, '{}'::uuid[]),
                  CASE WHEN deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[deal.assigned_to]::uuid[] END)
            AND NEW.visible_to = COALESCE(NULLIF(deal.assignee_ids, '{}'::uuid[]),
                  CASE WHEN deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[deal.assigned_to]::uuid[] END)
       )
       AND EXISTS (
         SELECT 1 FROM public.crm_generated_tasks generated
          WHERE generated.task_id=NEW.id AND generated.deal_id=NEW.crm_deal_id
            AND generated.kind='CONTACT_DISCUSSION'
       )
       AND NOT EXISTS (
         SELECT 1 FROM unnest(NEW.assignee_ids) selected(id)
          WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile
            WHERE profile.id=selected.id AND profile.is_active IS DISTINCT FROM false)
       ) THEN
      RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE'
       AND hrsys_private.valid_mq20_task_context(NEW.id, 'EXECUTION', NULL) THEN
      SELECT context.action INTO v_action
        FROM hrsys_private.mq20_task_write_context context
       WHERE context.token = NULLIF(current_setting('app.hrsys_mq20_task_context', true), '')::uuid
         AND context.backend_pid = pg_backend_pid()
         AND context.transaction_id = txid_current()
         AND context.task_id = NEW.id;
      v_allowed := CASE v_action
        WHEN 'START' THEN ARRAY['status', 'started_at', 'updated_at']
        WHEN 'WAIT' THEN ARRAY['work_state', 'resume_status', 'waiting_category', 'waiting_related_user_id', 'waiting_note', 'waiting_since', 'blocked_category', 'blocked_related_user_id', 'blocked_note', 'blocked_since', 'updated_at']
        WHEN 'BLOCK' THEN ARRAY['work_state', 'resume_status', 'blocked_category', 'blocked_related_user_id', 'blocked_note', 'blocked_since', 'waiting_category', 'waiting_related_user_id', 'waiting_note', 'waiting_since', 'updated_at']
        WHEN 'RESUME' THEN ARRAY['work_state', 'status', 'resume_status', 'waiting_category', 'waiting_related_user_id', 'waiting_note', 'waiting_since', 'blocked_category', 'blocked_related_user_id', 'blocked_note', 'blocked_since', 'updated_at']
        WHEN 'COMPLETE' THEN ARRAY['status', 'completed_at', 'work_state', 'resume_status', 'waiting_category', 'waiting_related_user_id', 'waiting_note', 'waiting_since', 'blocked_category', 'blocked_related_user_id', 'blocked_note', 'blocked_since', 'updated_at']
        ELSE ARRAY[]::text[]
      END;
      IF cardinality(v_allowed) > 0
         AND (to_jsonb(NEW) - v_allowed) = (to_jsonb(OLD) - v_allowed) THEN
        RETURN NEW;
      END IF;
    END IF;

    IF TG_OP = 'UPDATE'
       AND hrsys_private.valid_mq20_task_context(NEW.id, 'ASSIGN_SYNC', NULL)
       AND EXISTS (
         SELECT 1 FROM hrsys_private.mq20_task_write_context context
          WHERE context.token = NULLIF(current_setting('app.hrsys_mq20_task_context', true), '')::uuid
            AND context.backend_pid = pg_backend_pid()
            AND context.transaction_id = txid_current()
            AND context.task_id = NEW.id
            AND context.purpose = 'ASSIGN_SYNC'
            AND NEW.assignee_ids IS NOT DISTINCT FROM context.expected_assignees
            AND NEW.assignee_id IS NOT DISTINCT FROM context.expected_assignees[1]
            AND NEW.visible_to IS NOT DISTINCT FROM context.expected_assignees
       )
       AND (to_jsonb(NEW) - ARRAY['assignee_id', 'assignee_ids', 'visible_to', 'updated_at'])
           = (to_jsonb(OLD) - ARRAY['assignee_id', 'assignee_ids', 'visible_to', 'updated_at']) THEN
      RETURN NEW;
    END IF;
  END IF;

  RAISE EXCEPTION 'MQ-20 task access is view-only' USING ERRCODE = '42501';
END;
$function$;

-- Assignment synchronization is limited to the exact current CRM assignee
-- set, the task's three access fields, and a registry-backed active Contact task.
-- Production had no prior MQ-20 boundary trigger. The Contact-specific guard
-- from step 1 remains the identity authority; no Staging-wide Design registry
-- prerequisite is installed or imposed here.
CREATE TRIGGER mq20_task_service_view_only
BEFORE INSERT OR UPDATE OR DELETE ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.enforce_mq20_task_service_boundaries();
ALTER FUNCTION public.enforce_mq20_task_service_boundaries() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enforce_mq20_task_service_boundaries() FROM PUBLIC, anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION public.protect_task_access_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_token uuid;
  v_context hrsys_private.mq20_task_write_context%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR public.is_task_admin(auth.uid()) THEN RETURN NEW; END IF;
  IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'The task creator cannot be changed' USING ERRCODE = '42501';
  END IF;

  BEGIN
    v_token := NULLIF(current_setting('app.hrsys_mq20_task_context', true), '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_token := NULL;
  END;
  IF v_token IS NOT NULL THEN
    SELECT * INTO v_context
      FROM hrsys_private.mq20_task_write_context context
     WHERE context.token = v_token
       AND context.backend_pid = pg_backend_pid()
       AND context.transaction_id = txid_current()
       AND context.actor_id IS NOT DISTINCT FROM auth.uid()
       AND context.task_id = NEW.id
       AND context.purpose = 'ASSIGN_SYNC';
    IF FOUND
       AND hrsys_private.valid_mq20_task_context(NEW.id, 'ASSIGN_SYNC', NULL)
       AND NEW.assignee_ids IS NOT DISTINCT FROM v_context.expected_assignees
       AND NEW.assignee_id IS NOT DISTINCT FROM v_context.expected_assignees[1]
       AND NEW.visible_to IS NOT DISTINCT FROM v_context.expected_assignees
       AND (to_jsonb(NEW) - ARRAY['assignee_id', 'assignee_ids', 'visible_to', 'updated_at'])
           = (to_jsonb(OLD) - ARRAY['assignee_id', 'assignee_ids', 'visible_to', 'updated_at']) THEN
      RETURN NEW;
    END IF;
  END IF;

  IF auth.uid() <> OLD.created_by AND (
      NEW.assignee_id IS DISTINCT FROM OLD.assignee_id
      OR NEW.supervisor_id IS DISTINCT FROM OLD.supervisor_id
      OR NEW.project_id IS DISTINCT FROM OLD.project_id
      OR NEW.parent_task_id IS DISTINCT FROM OLD.parent_task_id
      OR NEW.visibility IS DISTINCT FROM OLD.visibility
      OR NEW.visible_to IS DISTINCT FROM OLD.visible_to
      OR NEW.watchers IS DISTINCT FROM OLD.watchers
  ) THEN
    RAISE EXCEPTION 'Only the task creator can change task access' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

-- Suppress only task-change and status-email triggers while a validated,
-- transaction-bound execution or assignment-sync context is active.
CREATE OR REPLACE FUNCTION public.notify_task_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
    IF TG_OP = 'UPDATE' AND hrsys_private.is_mq20_notification_suppressed(NEW.id) THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'INSERT' THEN
        PERFORM public.queue_task_notification(
            NEW.id, NEW.created_by,
            CASE WHEN NEW.parent_task_id IS NULL THEN 'task_created' ELSE 'subtask_created' END,
            CASE WHEN NEW.parent_task_id IS NULL THEN 'New task: ' ELSE 'New subtask: ' END || NEW.title
        );
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), CASE WHEN NEW.status = 'Pending Approval' THEN 'task_approval_requested' ELSE 'task_status_changed' END,
            CASE WHEN NEW.status = 'Pending Approval' THEN 'Completion approval requested for "' || NEW.title || '"'
            ELSE 'Task "' || NEW.title || '" moved ' ||
            CASE
                WHEN (CASE NEW.status WHEN 'todo' THEN 1 WHEN 'in_progress' THEN 2 WHEN 'review' THEN 3 WHEN 'completed' THEN 4 ELSE 0 END)
                   >= (CASE OLD.status WHEN 'todo' THEN 1 WHEN 'in_progress' THEN 2 WHEN 'review' THEN 3 WHEN 'completed' THEN 4 ELSE 0 END)
                THEN 'forward' ELSE 'backward'
            END || ' from ' || OLD.status || ' to ' || NEW.status END);
    ELSIF NEW.assignee_id IS DISTINCT FROM OLD.assignee_id THEN
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), 'task_assigned', 'Task assigned: ' || NEW.title);
    ELSE
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), 'task_updated', 'Task updated: ' || NEW.title);
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_task_status_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    recipient UUID;
    notification_row public.notifications%ROWTYPE;
    actor_name TEXT := COALESCE(public.email_profile_name(auth.uid()), 'System');
    status_label TEXT := COALESCE(NULLIF(BTRIM(NEW.status), ''), 'Unknown');
    task_message TEXT;
BEGIN
    IF hrsys_private.is_mq20_notification_suppressed(NEW.id)
       OR NEW.status IS NOT DISTINCT FROM OLD.status OR auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;
    task_message := format('Task "%s" status changed to "%s" by %s.',
        COALESCE(NEW.title, 'Untitled task'), status_label, actor_name);
    FOR recipient IN
        SELECT DISTINCT recipient_id FROM (
            SELECT NEW.assignee_id AS recipient_id
            UNION ALL SELECT unnest(COALESCE(NEW.assignee_ids, '{}'::UUID[]))
            UNION ALL SELECT unnest(COALESCE(NEW.watchers, '{}'::UUID[]))
        ) recipients
        WHERE recipient_id IS NOT NULL AND recipient_id IS DISTINCT FROM auth.uid()
    LOOP
        INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
        VALUES (recipient, task_message, 'task_status_changed', NEW.id, auth.uid(),
                '/?view=tasks&task=' || NEW.id,
                jsonb_build_object('task_title', NEW.title, 'from_status', OLD.status,
                                   'to_status', NEW.status, 'actor_name', actor_name))
        RETURNING * INTO notification_row;
        BEGIN
            INSERT INTO public.task_email_outbox(
                notification_id, task_id, recipient_id, recipient_email, subject, message,
                action_url, always_send, context_type, details
            )
            SELECT notification_row.id, NEW.id, profile.id, auth_user.email,
                   'Task status updated: ' || COALESCE(NEW.title, 'Untitled task'),
                   task_message, '/?view=tasks&task=' || NEW.id, TRUE, 'TASK',
                   jsonb_strip_nulls(jsonb_build_object(
                     'Task title', NEW.title,
                     'Task creator', public.email_profile_name(NEW.created_by),
                     'Updated by', actor_name,
                     'Assigned to', public.email_profile_name(NEW.assignee_id),
                     'From status', OLD.status,
                     'To status', NEW.status,
                     'Event', 'task_status_changed'
                   ))
              FROM public.profiles profile
              JOIN auth.users auth_user ON auth_user.id = profile.id
             WHERE profile.id = recipient AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Unable to queue Task status email for recipient %: %', recipient, SQLERRM;
        END;
    END LOOP;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_crm_contact_discussion_assignees()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_task_id uuid;
  v_task public.tasks%ROWTYPE;
  v_assignees uuid[];
  v_token uuid;
  v_previous_context text := current_setting('app.hrsys_mq20_task_context', true);
  v_existing_contact_task boolean;
BEGIN
  IF NEW.assigned_to IS NOT DISTINCT FROM OLD.assigned_to
     AND NEW.assignee_ids IS NOT DISTINCT FROM OLD.assignee_ids THEN
    RETURN NEW;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied for Contact Discussion assignment synchronization' USING ERRCODE = '42501';
  END IF;
  v_assignees := COALESCE(
    NULLIF(NEW.assignee_ids, '{}'::uuid[]),
    CASE WHEN NEW.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[NEW.assigned_to]::uuid[] END
  );
  IF cardinality(v_assignees) = 0 OR EXISTS (
      SELECT 1 FROM unnest(v_assignees) selected(id)
       WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false)
  ) THEN
    RAISE EXCEPTION 'CRM Contact Discussion tasks require active deal assignees' USING ERRCODE = '23514';
  END IF;

  SELECT mapping.task_id INTO v_task_id
    FROM public.crm_generated_tasks mapping
   WHERE mapping.deal_id = NEW.id AND mapping.kind = 'CONTACT_DISCUSSION'
   FOR UPDATE;
  IF NOT FOUND THEN
    SELECT EXISTS (SELECT 1 FROM public.tasks task
                    WHERE task.crm_deal_id = NEW.id AND task.crm_workflow_kind = 'CONTACT_DISCUSSION')
      INTO v_existing_contact_task;
    IF v_existing_contact_task THEN
      RAISE EXCEPTION 'Unregistered Contact Discussion task requires review; assignment update stopped' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  SELECT * INTO v_task FROM public.tasks WHERE id = v_task_id FOR UPDATE;
  IF NOT FOUND OR v_task.crm_deal_id IS DISTINCT FROM NEW.id
     OR v_task.crm_workflow_kind IS DISTINCT FROM 'CONTACT_DISCUSSION' THEN
    RAISE EXCEPTION 'CRM Contact Discussion registry identity mismatch; assignment update stopped' USING ERRCODE = '23514';
  END IF;
  -- Archived records remain immutable. Keep CRM and task assignment changes atomic.
  IF v_task.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Archived Contact Discussion tasks are immutable; assignment update stopped' USING ERRCODE = '42501';
  END IF;
  IF v_task.task_list_id IS NOT NULL THEN
    RAISE EXCEPTION 'Contact Discussion task unexpectedly belongs to a task list; assignment update stopped' USING ERRCODE = '23514';
  END IF;
  IF v_task.assignee_id = v_assignees[1]
     AND v_task.assignee_ids IS NOT DISTINCT FROM v_assignees
     AND v_task.visible_to IS NOT DISTINCT FROM v_assignees THEN
    RETURN NEW;
  END IF;

  v_token := gen_random_uuid();
  INSERT INTO hrsys_private.mq20_task_write_context(
    token, backend_pid, transaction_id, actor_id, task_id, deal_id, purpose, action, expected_assignees
  ) VALUES (v_token, pg_backend_pid(), txid_current(), auth.uid(), v_task_id, NEW.id,
            'ASSIGN_SYNC', 'ASSIGN_SYNC', v_assignees);
  PERFORM set_config('app.hrsys_mq20_task_context', v_token::text, true);
  BEGIN
    UPDATE public.tasks
       SET assignee_id = v_assignees[1], assignee_ids = v_assignees, visible_to = v_assignees
     WHERE id = v_task_id;
    DELETE FROM hrsys_private.mq20_task_write_context WHERE token = v_token;
    PERFORM set_config('app.hrsys_mq20_task_context', COALESCE(v_previous_context, ''), true);
  EXCEPTION WHEN OTHERS THEN
    DELETE FROM hrsys_private.mq20_task_write_context WHERE token = v_token;
    PERFORM set_config('app.hrsys_mq20_task_context', COALESCE(v_previous_context, ''), true);
    RAISE;
  END;
  RETURN NEW;
END;
$function$;
ALTER FUNCTION public.sync_crm_contact_discussion_assignees() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.sync_crm_contact_discussion_assignees() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER crm_sync_contact_discussion_assignees
AFTER UPDATE OF assigned_to, assignee_ids ON public.crm_deals
FOR EACH ROW EXECUTE FUNCTION public.sync_crm_contact_discussion_assignees();

CREATE OR REPLACE FUNCTION public.execute_crm_contact_discussion_task(
  p_task_id uuid,
  p_action text,
  p_category text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_action text := UPPER(BTRIM(COALESCE(p_action, '')));
  v_initial_deal_id uuid;
  v_deal public.crm_deals%ROWTYPE;
  v_task public.tasks%ROWTYPE;
  v_assignees uuid[];
  v_category text := UPPER(BTRIM(COALESCE(p_category, '')));
  v_note text := NULLIF(BTRIM(p_note), '');
  v_token uuid;
  v_previous_context text := current_setting('app.hrsys_mq20_task_context', true);
  v_changed boolean := false;
  v_next_status text;
  v_now timestamptz := now();
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()) THEN
    RAISE EXCEPTION 'Scoped MQ-20 execution is unavailable' USING ERRCODE = '42501';
  END IF;
  IF v_action NOT IN ('START', 'WAIT', 'BLOCK', 'RESUME', 'COMPLETE') THEN
    RAISE EXCEPTION 'Unsupported Contact Discussion action' USING ERRCODE = '22023';
  END IF;
  SELECT task.crm_deal_id INTO v_initial_deal_id FROM public.tasks task WHERE task.id = p_task_id;
  IF v_initial_deal_id IS NULL THEN RAISE EXCEPTION 'Contact Discussion task not found' USING ERRCODE = 'P0002'; END IF;
  -- Global lock order is CRM deal then task; the assignment-sync trigger follows it.
  SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_initial_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
  SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND OR v_task.crm_deal_id IS DISTINCT FROM v_deal.id
     OR v_task.crm_workflow_kind IS DISTINCT FROM 'CONTACT_DISCUSSION' THEN
    RAISE EXCEPTION 'Task is not the registered CRM Contact Discussion task' USING ERRCODE = '42501';
  END IF;
  IF v_task.archived_at IS NOT NULL THEN RAISE EXCEPTION 'Archived tasks are read-only' USING ERRCODE = '42501'; END IF;
  IF v_task.task_list_id IS NOT NULL THEN RAISE EXCEPTION 'Contact Discussion task list context is invalid' USING ERRCODE = '42501'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.crm_generated_tasks mapping
     WHERE mapping.deal_id = v_deal.id AND mapping.task_id = v_task.id AND mapping.kind = 'CONTACT_DISCUSSION'
  ) THEN RAISE EXCEPTION 'Contact Discussion registry identity is missing' USING ERRCODE = '42501'; END IF;
  IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN RAISE EXCEPTION 'Lost CRM deals are read-only' USING ERRCODE = '42501'; END IF;
  v_assignees := COALESCE(
    NULLIF(v_deal.assignee_ids, '{}'::uuid[]),
    CASE WHEN v_deal.assigned_to IS NULL THEN '{}'::uuid[] ELSE ARRAY[v_deal.assigned_to]::uuid[] END
  );
  IF cardinality(v_assignees) = 0
     OR EXISTS (
       SELECT 1 FROM unnest(v_assignees) selected(id)
        WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile WHERE profile.id = selected.id AND profile.is_active IS DISTINCT FROM false)
     ) THEN
    RAISE EXCEPTION 'Current CRM assignees are invalid; execution stopped' USING ERRCODE = '42501';
  END IF;
  IF NOT auth.uid() = ANY(v_assignees) THEN RAISE EXCEPTION 'Only a current CRM deal assignee may execute this task' USING ERRCODE = '42501'; END IF;
  IF v_task.assignee_id IS DISTINCT FROM v_assignees[1]
     OR v_task.assignee_ids IS DISTINCT FROM v_assignees
     OR v_task.visible_to IS DISTINCT FROM v_assignees THEN
    RAISE EXCEPTION 'Generated task assignment is out of sync; ask a CRM administrator to review it' USING ERRCODE = '42501';
  END IF;
  IF public.task_dependency_blocked(p_task_id) THEN
    RAISE EXCEPTION 'Task is waiting for a previous task to complete' USING ERRCODE = '42501';
  END IF;
  IF v_action IN ('WAIT', 'BLOCK') THEN
    IF NOT public.productivity_validate_category(v_category, v_action = 'BLOCK') THEN
      RAISE EXCEPTION 'Invalid wait/block category' USING ERRCODE = '22023';
    END IF;
  ELSIF p_category IS NOT NULL OR p_note IS NOT NULL THEN
    RAISE EXCEPTION 'Category and note are only accepted for wait/block actions' USING ERRCODE = '22023';
  END IF;
  IF v_action IN ('WAIT', 'BLOCK') AND LOWER(BTRIM(v_task.status)) NOT IN ('todo', 'in_progress', 'review') THEN
    RAISE EXCEPTION 'This Contact task state cannot be put on hold' USING ERRCODE = '22023';
  END IF;
  IF v_action IN ('START', 'RESUME') AND LOWER(BTRIM(v_task.status)) = 'pending approval' THEN
    RAISE EXCEPTION 'Approval-pending tasks cannot be started' USING ERRCODE = '22023';
  END IF;
  IF v_action = 'START' AND LOWER(BTRIM(v_task.status)) = 'completed' THEN RAISE EXCEPTION 'Completed tasks cannot be started' USING ERRCODE = '22023'; END IF;
  IF v_action = 'COMPLETE' AND LOWER(BTRIM(v_task.status)) = 'pending approval' THEN RAISE EXCEPTION 'Approval-pending tasks cannot be completed' USING ERRCODE = '42501'; END IF;
  IF v_action = 'START' AND LOWER(BTRIM(v_task.status)) NOT IN ('todo', 'in_progress') THEN
    RAISE EXCEPTION 'Only to-do or in-progress Contact tasks can be started' USING ERRCODE = '22023';
  END IF;
  IF v_action = 'RESUME' AND LOWER(BTRIM(v_task.status)) NOT IN ('todo', 'in_progress', 'review') THEN
    RAISE EXCEPTION 'This Contact task state cannot be resumed' USING ERRCODE = '22023';
  END IF;
  IF v_action = 'RESUME' AND NULLIF(BTRIM(v_task.resume_status), '') IS NOT NULL
     AND LOWER(BTRIM(v_task.resume_status)) NOT IN ('todo', 'in_progress', 'review') THEN
    RAISE EXCEPTION 'Stored Contact task resume state is invalid' USING ERRCODE = '22023';
  END IF;
  IF v_action = 'COMPLETE' AND LOWER(BTRIM(v_task.status)) NOT IN ('todo', 'in_progress', 'review', 'completed') THEN
    RAISE EXCEPTION 'Approval or historical CRM states cannot be completed through this RPC' USING ERRCODE = '42501';
  END IF;
  IF v_action = 'START' AND v_task.work_state <> 'ACTIVE' THEN RAISE EXCEPTION 'Resume the task before starting work' USING ERRCODE = '22023'; END IF;

  v_token := gen_random_uuid();
  INSERT INTO hrsys_private.mq20_task_write_context(
    token, backend_pid, transaction_id, actor_id, task_id, deal_id, purpose, action, expected_assignees
  ) VALUES (v_token, pg_backend_pid(), txid_current(), auth.uid(), v_task.id, v_deal.id,
            'EXECUTION', v_action, v_assignees);
  PERFORM set_config('app.hrsys_mq20_task_context', v_token::text, true);
  BEGIN
    IF v_action = 'START' THEN
      IF v_task.status IS DISTINCT FROM 'in_progress' OR v_task.started_at IS NULL THEN
        UPDATE public.tasks SET status = 'in_progress', started_at = COALESCE(started_at, v_now) WHERE id = p_task_id;
        INSERT INTO public.task_activity(task_id, actor_id, action, from_status, to_status, metadata)
        VALUES (p_task_id, auth.uid(), 'TASK_STARTED', v_task.status, 'in_progress', '{}'::jsonb);
        v_changed := true;
      END IF;
    ELSIF v_action = 'WAIT' THEN
      IF v_task.work_state IS DISTINCT FROM 'WAITING' THEN
        UPDATE public.tasks SET work_state = 'WAITING', resume_status = status,
          waiting_category = v_category, waiting_related_user_id = NULL,
          waiting_note = v_note, waiting_since = v_now,
          blocked_category = NULL, blocked_related_user_id = NULL, blocked_note = NULL, blocked_since = NULL
        WHERE id = p_task_id;
        INSERT INTO public.task_waiting_history(task_id, actor_id, category, related_user_id, note, started_at)
        VALUES (p_task_id, auth.uid(), v_category, NULL, v_note, v_now);
        INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
        VALUES (p_task_id, auth.uid(), 'TASK_WAITING', jsonb_build_object('category', v_category, 'note', v_note));
        v_changed := true;
      END IF;
    ELSIF v_action = 'BLOCK' THEN
      IF v_task.work_state IS DISTINCT FROM 'BLOCKED' THEN
        UPDATE public.tasks SET work_state = 'BLOCKED', resume_status = status,
          blocked_category = v_category, blocked_related_user_id = NULL,
          blocked_note = v_note, blocked_since = v_now,
          waiting_category = NULL, waiting_related_user_id = NULL, waiting_note = NULL, waiting_since = NULL
        WHERE id = p_task_id;
        INSERT INTO public.task_blocker_history(task_id, actor_id, category, related_user_id, note, created_at)
        VALUES (p_task_id, auth.uid(), v_category, NULL, v_note, v_now);
        INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
        VALUES (p_task_id, auth.uid(), 'TASK_BLOCKED', jsonb_build_object('category', v_category, 'note', v_note));
        v_changed := true;
      END IF;
    ELSIF v_action = 'RESUME' THEN
      IF v_task.work_state IS DISTINCT FROM 'ACTIVE' THEN
        v_next_status := COALESCE(NULLIF(LOWER(BTRIM(v_task.resume_status)), ''), CASE WHEN v_task.started_at IS NULL THEN 'todo' ELSE 'in_progress' END);
        UPDATE public.tasks SET work_state = 'ACTIVE', status = v_next_status,
          waiting_category = NULL, waiting_related_user_id = NULL, waiting_note = NULL, waiting_since = NULL,
          blocked_category = NULL, blocked_related_user_id = NULL, blocked_note = NULL, blocked_since = NULL,
          resume_status = NULL
        WHERE id = p_task_id;
        UPDATE public.task_waiting_history SET resumed_at = v_now, resumed_by = auth.uid()
         WHERE task_id = p_task_id AND resumed_at IS NULL;
        UPDATE public.task_blocker_history SET resolved_at = v_now, resolved_by = auth.uid()
         WHERE task_id = p_task_id AND resolved_at IS NULL;
        INSERT INTO public.task_activity(task_id, actor_id, action, from_status, to_status, metadata)
        VALUES (p_task_id, auth.uid(), 'TASK_RESUMED', v_task.status, v_next_status,
                jsonb_build_object('previous_work_state', v_task.work_state));
        v_changed := true;
      END IF;
    ELSIF v_action = 'COMPLETE' THEN
      IF v_task.status IS DISTINCT FROM 'completed' THEN
        UPDATE public.tasks SET status = 'completed', completed_at = COALESCE(completed_at, v_now),
          work_state = 'ACTIVE', waiting_category = NULL, waiting_related_user_id = NULL, waiting_note = NULL, waiting_since = NULL,
          blocked_category = NULL, blocked_related_user_id = NULL, blocked_note = NULL, blocked_since = NULL, resume_status = NULL
        WHERE id = p_task_id;
        INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
        VALUES (p_task_id, auth.uid(), 'TASK_COMPLETED', '{}'::jsonb);
        v_changed := true;
      END IF;
    END IF;
    DELETE FROM hrsys_private.mq20_task_write_context WHERE token = v_token;
    PERFORM set_config('app.hrsys_mq20_task_context', COALESCE(v_previous_context, ''), true);
  EXCEPTION WHEN OTHERS THEN
    DELETE FROM hrsys_private.mq20_task_write_context WHERE token = v_token;
    PERFORM set_config('app.hrsys_mq20_task_context', COALESCE(v_previous_context, ''), true);
    RAISE;
  END;

  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'action', lower(v_action),
    'status', (SELECT task.status FROM public.tasks task WHERE task.id = p_task_id),
    'work_state', (SELECT task.work_state FROM public.tasks task WHERE task.id = p_task_id),
    'changed', v_changed,
    'actor_id', auth.uid()
  );
END;
$function$;
ALTER FUNCTION public.execute_crm_contact_discussion_task(uuid, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.execute_crm_contact_discussion_task(uuid, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.execute_crm_contact_discussion_task(uuid, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.execute_crm_contact_discussion_task(uuid, text, text, text) IS
  'Allows current MQ-20 CRM assignees to start, wait, block, resume, or complete only their active registry-backed Contact Discussion task; does not activate successors or emit task/email notifications.';

NOTIFY pgrst, 'reload schema';
COMMIT;
