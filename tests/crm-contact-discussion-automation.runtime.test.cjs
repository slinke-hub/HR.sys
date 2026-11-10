/* eslint-env node */
// Disposable PostgreSQL behavior test. It starts only a new temp cluster bound
// to 127.0.0.1 and imports tracked CRM functions, exact exported Staging guards,
// and synthetic schema/data.
const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const postgresDocker = require('./helpers/postgres-docker-runtime.cjs');

const root = path.join(__dirname, '..');
const dockerMode = process.env.HRSYS_PG_DOCKER === '1';
const pgBin = process.env.PG_BIN || 'C:\\Program Files\\PostgreSQL\\18\\bin';
const initdb = path.join(pgBin, 'initdb.exe');
const pgCtl = path.join(pgBin, 'pg_ctl.exe');
const postgres = path.join(pgBin, 'postgres.exe');
const psql = path.join(pgBin, 'psql.exe');
const pgIsReady = path.join(pgBin, 'pg_isready.exe');
if (!dockerMode) for (const binary of [initdb, pgCtl, postgres, psql, pgIsReady]) assert.ok(fs.existsSync(binary), `Missing disposable PostgreSQL utility: ${binary}`);

const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const extractFunction = (source, name) => {
  const expression = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\n\\$\\$;`, 'i');
  const match = source.match(expression);
  assert.ok(match, `Could not extract tracked function ${name}`);
  return match[0];
};

const shared = read('supabase/migrations/20260917090000_shared_business_logic_services.sql');
const dealBackend = read('supabase/migrations/20260930102000_deal_backend_services.sql');
const mq20Access = read('supabase/migrations/20260908110000_marketing_manager_employee_task_access.sql');
const productivityA = read('supabase/migrations/20260930104000_productivity_phase_a.sql');
const productivityB = read('supabase/migrations/20260930105000_productivity_phase_b.sql');
const migration = read('supabase/migrations/20261109100000_crm_contact_discussion_automation.sql');
const mq20Migration = read('supabase/migrations/20261109110000_mq20_contact_discussion_execution.sql');
const compatibilityMigration = read('supabase/migrations/20261110100000_crm_staging_compatibility_security.sql');
const stagingMq20Functions = read('tests/fixtures/staging-mq20-security-functions.sql');
const stagingCrmWorkflow = read('tests/fixtures/staging-crm-workflow-transition.sql');
const stagingQueueDefinition = JSON.parse(read('tests/fixtures/staging-queue-task-notification.definition.json')).definition;
const stagingCrmExistingFunctionsTemplate = read('tests/fixtures/staging-crm-existing-functions.sql');
assert.ok(stagingCrmExistingFunctionsTemplate.includes('-- STAGING_QUEUE_TASK_NOTIFICATION_DEFINITION'), 'Verified Staging notification definition placeholder is missing');
const stagingCrmExistingFunctions = stagingCrmExistingFunctionsTemplate.replace('-- STAGING_QUEUE_TASK_NOTIFICATION_DEFINITION', `${stagingQueueDefinition};`);
const stagingCrmAttachmentHelpers = read('tests/fixtures/staging-crm-attachment-helpers.sql');
const stagingCrmPrerequisiteStubs = String.raw`
CREATE OR REPLACE FUNCTION public.is_ines_modani_task(uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.is_ines_modani_task_list(uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.can_assign_tasks_company_wide(uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.can_marketing_manager_edit_task(uuid,uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.can_view_task_via_employee_grant(uuid,uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.can_view_task_list(uuid,uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.can_view_task_list_via_employee_grant(uuid,uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.is_project_portfolio_admin(uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
`;
const taskCreate = extractFunction(shared, 'create_task_secure');
const stageChange = extractFunction(shared, 'change_crm_deal_stage');
const dealRead = extractFunction(dealBackend, 'get_crm_deal_secure');
const productivityValidateCategory = extractFunction(productivityA, 'productivity_validate_category');
const taskDependencyBlocked = extractFunction(productivityB, 'task_dependency_blocked');

const baseline = String.raw`
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;
CREATE SCHEMA auth;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO PUBLIC;
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY, employee_id text, is_active boolean DEFAULT true,
  crm_access boolean NOT NULL DEFAULT false, financial_access boolean NOT NULL DEFAULT false,
  role text, task_email_notifications boolean DEFAULT false,
  full_name text, display_name text, display_name_ar text
);
CREATE TABLE public.crm_clients (id uuid PRIMARY KEY, name text, company text);
CREATE TABLE public.crm_deals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), client_id uuid, title text NOT NULL,
  amount numeric DEFAULT 0, stage text NOT NULL DEFAULT 'LEAD', closing_date date,
  assigned_to uuid, event_type text, first_contact_date date, contact_method text,
  lead_source text, technical_description text, created_by uuid,
  workflow_status text DEFAULT 'NOT_STARTED', approval_type text, design_task_id uuid,
  proposal_sent_at timestamptz, lost_reason text,
  CONSTRAINT crm_deals_stage_check CHECK (stage IN ('LEAD','QUALIFICATION','PITCH','PROPOSAL','NEGOTIATION','WON','LOST'))
);
CREATE TABLE public.crm_deal_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), deal_id uuid, action text,
  from_status text, to_status text, note text, actor_id uuid, created_at timestamptz DEFAULT now()
);
-- Simulate a legacy Production Lost deal before the migration backfill.
INSERT INTO public.crm_deals(id,client_id,title,stage,assigned_to,created_by,workflow_status)
VALUES ('00000000-0000-4000-8000-000000000205','00000000-0000-4000-8000-000000000100','Legacy lost deal','LOST','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','NOT_STARTED');
CREATE TABLE public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text NOT NULL, description text,
  assignee_id uuid, assignee_ids uuid[] NOT NULL DEFAULT '{}', supervisor_id uuid,
  created_by uuid NOT NULL, due_date date, status text DEFAULT 'todo', priority text DEFAULT 'medium',
  category text DEFAULT 'General', title_i18n jsonb DEFAULT '{}', description_i18n jsonb DEFAULT '{}',
  start_date date, end_date date, estimated_time integer, visibility text DEFAULT 'public',
  project_id uuid, tags text[] DEFAULT '{}', visible_to uuid[] DEFAULT '{}', content_type text,
  source_link text, upload_link text, department text, sub_type text, watchers uuid[] DEFAULT '{}',
  parent_task_id uuid, marketing_department text, content_links text[] DEFAULT '{}',
  submission_links text[] DEFAULT '{}', delivery_status text, task_list_id uuid,
  repeat_type text DEFAULT 'NONE', repeat_interval integer DEFAULT 1,
  notify_via_email boolean DEFAULT false, attachments jsonb DEFAULT '[]', crm_deal_id uuid, crm_workflow_kind text,
  CONSTRAINT tasks_crm_workflow_kind_check CHECK (crm_workflow_kind IS NULL OR crm_workflow_kind IN ('QUOTE_PROPOSAL_DESIGN','CONTACT_DISCUSSION'))
);
-- Reproduce Staging's existing legacy registry, including its preserved Design
-- mapping and effective lack of client table access.
CREATE TABLE public.crm_generated_tasks (
  deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('CONTACT_DISCUSSION','QUOTE_PROPOSAL_DESIGN')),
  task_id uuid NOT NULL UNIQUE REFERENCES public.tasks(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
  PRIMARY KEY (deal_id, kind)
);
ALTER TABLE public.crm_generated_tasks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crm_generated_tasks FROM PUBLIC, anon, authenticated;
CREATE TABLE auth.users(id uuid PRIMARY KEY, email text);
CREATE TABLE public.projects(
  id uuid PRIMARY KEY,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  project_manager_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_people uuid[] DEFAULT '{}'
);
CREATE TABLE public.departments(name text, head_id uuid);
CREATE TABLE public.task_comments(id bigserial PRIMARY KEY, task_id uuid NOT NULL, user_id uuid NOT NULL, content text NOT NULL, attachments jsonb DEFAULT '[]', created_at timestamptz DEFAULT now());
CREATE TABLE public.notifications(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid, message text, event_type text,
  task_id uuid, actor_id uuid, action_url text, metadata jsonb, created_at timestamptz DEFAULT now()
);
CREATE TABLE public.task_email_outbox(
  id bigserial PRIMARY KEY, notification_id uuid, task_id uuid, recipient_id uuid, recipient_email text,
  subject text, message text, action_url text, comment_text text, attachment_links jsonb,
  always_send boolean, context_type text, details jsonb
);
CREATE TABLE public.task_attachments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL, file_url text NOT NULL,
  file_name text NOT NULL, file_type text, file_size bigint, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.crm_design_task_approval_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
  step_order integer NOT NULL CHECK (step_order BETWEEN 1 AND 5),
  stage_key text NOT NULL CHECK (stage_key IN ('CEO','GENERAL_MANAGER','MQ_04','MQ_05','MARKETING_MANAGER')),
  approver_id uuid NOT NULL REFERENCES public.profiles(id),
  status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','APPROVED','REJECTED')),
  decision_note text, decided_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (task_id, stage_key)
);
INSERT INTO public.crm_deals(id,client_id,title,stage,created_by,design_task_id)
VALUES ('00000000-0000-4000-8000-000000000206',NULL,'Legacy Design deal','PROPOSAL',
        '00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000306');
INSERT INTO public.crm_deals(id,client_id,title,stage,assigned_to,created_by)
VALUES ('00000000-0000-4000-8000-000000000207',NULL,'Legacy Contact deal','LEAD',
        '00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003');
INSERT INTO public.tasks(id,title,created_by,crm_deal_id,crm_workflow_kind)
VALUES ('00000000-0000-4000-8000-000000000306','Preserved legacy Design task',
        '00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000206','QUOTE_PROPOSAL_DESIGN');
INSERT INTO public.tasks(id,title,created_by,assignee_id,assignee_ids,crm_deal_id,crm_workflow_kind)
VALUES ('00000000-0000-4000-8000-000000000307','Preserved legacy Contact task',
        '00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001','{}',
        '00000000-0000-4000-8000-000000000207','CONTACT_DISCUSSION');
INSERT INTO public.crm_generated_tasks(deal_id,kind,task_id)
VALUES ('00000000-0000-4000-8000-000000000206','QUOTE_PROPOSAL_DESIGN','00000000-0000-4000-8000-000000000306'),
       ('00000000-0000-4000-8000-000000000207','CONTACT_DISCUSSION','00000000-0000-4000-8000-000000000307');
CREATE OR REPLACE FUNCTION public.can_access_crm(p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT COALESCE((SELECT crm_access FROM public.profiles WHERE id=p_user_id), false)
$$;
CREATE OR REPLACE FUNCTION public.can_view_business_financials(p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT COALESCE((SELECT financial_access FROM public.profiles WHERE id=p_user_id), false)
$$;
CREATE OR REPLACE FUNCTION public.can_access_project(p_project_id uuid, p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.can_add_task_to_list(p_list_id uuid, p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.is_task_admin(p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.email_profile_name(p_user_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT COALESCE(profile.id::text, 'Synthetic') FROM public.profiles profile WHERE profile.id = p_user_id
$$;
` + '\n' + stagingMq20Functions + String.raw`
CREATE TRIGGER mq20_task_service_view_only BEFORE INSERT OR DELETE OR UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.enforce_mq20_task_service_boundaries();
CREATE TRIGGER protect_crm_generated_task_identity BEFORE INSERT OR UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.protect_crm_generated_task_identity();
CREATE TRIGGER protect_task_access_fields_trigger BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.protect_task_access_fields();
` + '\n' + stagingCrmWorkflow + '\n' + stagingCrmPrerequisiteStubs + '\n' + stagingCrmExistingFunctions + '\n' + stagingCrmAttachmentHelpers;

const assertions = String.raw`
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000207','QUALIFICATION');
RESET ROLE;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.tasks WHERE crm_deal_id='00000000-0000-4000-8000-000000000207'
      AND crm_workflow_kind='CONTACT_DISCUSSION') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.crm_generated_tasks
       WHERE deal_id='00000000-0000-4000-8000-000000000207'
         AND kind='CONTACT_DISCUSSION'
         AND task_id='00000000-0000-4000-8000-000000000307') THEN
    RAISE EXCEPTION 'matching legacy Contact task/registry entry was not reused';
  END IF;
END $$;
DO $$
DECLARE ordered_names text[];
BEGIN
  SELECT array_agg(trigger_row.tgname ORDER BY trigger_row.tgname) INTO ordered_names
  FROM pg_trigger trigger_row
  WHERE trigger_row.tgrelid='public.tasks'::regclass
    AND trigger_row.tgname IN ('crm_contact_discussion_task_guard','protect_crm_generated_task_identity');
  IF ordered_names IS DISTINCT FROM ARRAY['crm_contact_discussion_task_guard','protect_crm_generated_task_identity']::text[] THEN
    RAISE EXCEPTION 'Contact registration trigger does not precede the legacy identity guard';
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id='00000000-0000-4000-8000-000000000205'
                 AND stage='LOST' AND assigned_to='00000000-0000-4000-8000-000000000001'
                 AND cardinality(assignee_ids)=0) THEN
    RAISE EXCEPTION 'migration altered a protected legacy Lost deal';
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.create_task_secure(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_crm_deal_stage(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_crm_deal_secure(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_crm_deal_secure(uuid,jsonb) TO authenticated;
GRANT SELECT ON public.profiles, public.crm_deals, public.crm_deal_activity, public.tasks TO authenticated;
INSERT INTO public.crm_deals(id,client_id,title,stage,assigned_to,created_by,workflow_status)
VALUES ('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000100','Single assignment','LEAD','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','NOT_STARTED'),
       ('00000000-0000-4000-8000-000000000202','00000000-0000-4000-8000-000000000100','No assignment','LEAD',NULL,'00000000-0000-4000-8000-000000000003','NOT_STARTED'),
       ('00000000-0000-4000-8000-000000000203','00000000-0000-4000-8000-000000000100','Approval history','LEAD','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','NOT_STARTED'),
       ('00000000-0000-4000-8000-000000000204','00000000-0000-4000-8000-000000000100','Historical negotiation','NEGOTIATION','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','APPROVED');
UPDATE public.crm_deals SET amount=987654 WHERE id='00000000-0000-4000-8000-000000000201';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
DO $$ DECLARE deal_data jsonb; BEGIN
  deal_data := public.get_crm_deal_secure('00000000-0000-4000-8000-000000000201');
  IF deal_data->>'amount' IS NOT NULL THEN RAISE EXCEPTION 'Unauthorized synthetic CRM user received financial amount'; END IF;
END $$;
-- Inspect the generated row as the database owner: RLS correctly hides a
-- private assignee task from the separate CRM stage-changing actor.
RESET ROLE;
DO $$
DECLARE created jsonb; deal_id uuid; task_count integer; task_row public.tasks%ROWTYPE; failed boolean;
BEGIN
  -- The active stage-changing CRM employee differs from the assigned employee.
  PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','QUALIFICATION');
  SELECT count(*) INTO task_count FROM public.tasks task
   WHERE task.crm_deal_id='00000000-0000-4000-8000-000000000201' AND task.crm_workflow_kind='CONTACT_DISCUSSION';
  SELECT * INTO task_row FROM public.tasks task
   WHERE task.crm_deal_id='00000000-0000-4000-8000-000000000201' AND task.crm_workflow_kind='CONTACT_DISCUSSION';
  IF task_count <> 1 OR task_row.assignee_id <> '00000000-0000-4000-8000-000000000001'
     OR task_row.assignee_ids <> ARRAY['00000000-0000-4000-8000-000000000001']::uuid[]
     OR task_row.visibility <> 'private'
     OR task_row.visible_to <> ARRAY['00000000-0000-4000-8000-000000000001']::uuid[]
     OR task_row.created_by <> auth.uid() THEN RAISE EXCEPTION 'single assignee or actor separation failed: count=%, assignee_id=%, assignee_ids=%, visibility=%, visible_to=%, created_by=%, actor=%', task_count, task_row.assignee_id, task_row.assignee_ids, task_row.visibility, task_row.visible_to, task_row.created_by, auth.uid(); END IF;
  PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','QUALIFICATION');
  PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','LEAD');
  PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','QUALIFICATION');
  SELECT count(*) INTO task_count FROM public.tasks WHERE crm_deal_id='00000000-0000-4000-8000-000000000201' AND crm_workflow_kind='CONTACT_DISCUSSION';
  IF task_count <> 1 THEN RAISE EXCEPTION 'retry/re-entry created a duplicate task'; END IF;
END $$;
SET ROLE authenticated;

DO $$ DECLARE helper_blocked boolean := false; task_blocked boolean := false; BEGIN
  BEGIN
    PERFORM public.create_crm_contact_discussion_task('00000000-0000-4000-8000-000000000201');
  EXCEPTION WHEN insufficient_privilege THEN helper_blocked := true; END;
  IF NOT helper_blocked THEN RAISE EXCEPTION 'authenticated user could call the privileged CRM task helper'; END IF;
  BEGIN
    PERFORM public.create_task_secure(jsonb_build_object(
      'title','Forged Contact task','assignee_id','00000000-0000-4000-8000-000000000001',
      'assignee_ids',jsonb_build_array('00000000-0000-4000-8000-000000000001'),
      'crm_deal_id','00000000-0000-4000-8000-000000000201','crm_workflow_kind','CONTACT_DISCUSSION'));
  EXCEPTION WHEN insufficient_privilege THEN task_blocked := true; END;
  IF NOT task_blocked THEN RAISE EXCEPTION 'authenticated user bypassed the Contact task creation guard'; END IF;
END $$;
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SELECT set_config('app.crm_contact_discussion_creation','on',false);
DO $$ DECLARE forged_blocked boolean := false; BEGIN
  BEGIN
    PERFORM public.create_task_secure(jsonb_build_object(
      'title','Synthetic unauthorized Contact task',
      'assignee_id','00000000-0000-4000-8000-000000000001',
      'assignee_ids',jsonb_build_array('00000000-0000-4000-8000-000000000001'),
      'crm_deal_id','00000000-0000-4000-8000-000000000201',
      'crm_workflow_kind','CONTACT_DISCUSSION'));
  EXCEPTION WHEN insufficient_privilege THEN forged_blocked := true; END;
  IF NOT forged_blocked THEN RAISE EXCEPTION 'non-CRM user spoofed the task-creation context'; END IF;
END $$;
RESET ROLE;
SELECT set_config('app.crm_contact_discussion_creation','',false);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);

DO $$ DECLARE created jsonb; deal_id uuid; task_row public.tasks%ROWTYPE; BEGIN
  created := public.create_crm_deal_secure(jsonb_build_object(
    'title','Synthetic multi-assignee deal','client_id','00000000-0000-4000-8000-000000000100',
    'first_contact_date','2026-11-09','contact_method','Phone call',
    'assigned_to','00000000-0000-4000-8000-000000000001',
    'assignee_ids',jsonb_build_array('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002')));
  deal_id := (created->>'id')::uuid;
  IF created->'assignee_ids' <> jsonb_build_array('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002') THEN
    RAISE EXCEPTION 'create RPC did not return both deal assignees';
  END IF;
  PERFORM public.change_crm_deal_stage(deal_id,'QUALIFICATION');
  SELECT * INTO task_row FROM public.tasks WHERE crm_deal_id=deal_id AND crm_workflow_kind='CONTACT_DISCUSSION';
  IF task_row.assignee_ids <> ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[]
     OR task_row.assignee_id <> '00000000-0000-4000-8000-000000000001'
     OR task_row.visibility <> 'private'
     OR task_row.visible_to <> ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[] THEN
    RAISE EXCEPTION 'multi-assignee recipients were not preserved';
  END IF;
  BEGIN
    PERFORM public.update_crm_deal_secure(deal_id,jsonb_build_object(
      'assigned_to','00000000-0000-4000-8000-000000000004',
      'assignee_ids',jsonb_build_array('00000000-0000-4000-8000-000000000004')));
    RAISE EXCEPTION 'inactive assignee unexpectedly accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  IF NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id=deal_id AND assignee_ids=ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[]) THEN
    RAISE EXCEPTION 'failed unauthorized assignment changed deal state';
  END IF;
END $$;

DO $$ DECLARE failed boolean := false; BEGIN
  BEGIN
    PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000202','QUALIFICATION');
  EXCEPTION WHEN check_violation THEN failed := true; END;
  IF NOT failed THEN RAISE EXCEPTION 'unassigned deal transition unexpectedly succeeded'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id='00000000-0000-4000-8000-000000000202' AND stage='LEAD' AND cardinality(assignee_ids)=0)
     OR EXISTS (SELECT 1 FROM public.tasks WHERE crm_deal_id='00000000-0000-4000-8000-000000000202') THEN
    RAISE EXCEPTION 'unassigned transition was not atomic';
  END IF;
END $$;

DO $$ DECLARE failed boolean := false; BEGIN
  BEGIN PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000203','NEGOTIATION');
  EXCEPTION WHEN insufficient_privilege THEN failed := true; END;
  IF NOT failed THEN RAISE EXCEPTION 'Negotiation bypassed existing approval requirement'; END IF;
END $$;
RESET ROLE;
UPDATE public.tasks SET status='in_progress'
 WHERE crm_deal_id='00000000-0000-4000-8000-000000000201'
   AND crm_workflow_kind='CONTACT_DISCUSSION';
DO $$ DECLARE identity_blocked boolean := false; BEGIN
  BEGIN
    UPDATE public.tasks SET crm_deal_id='00000000-0000-4000-8000-000000000202'
     WHERE crm_deal_id='00000000-0000-4000-8000-000000000201'
       AND crm_workflow_kind='CONTACT_DISCUSSION';
  EXCEPTION WHEN insufficient_privilege THEN identity_blocked := true; END;
  IF NOT identity_blocked THEN RAISE EXCEPTION 'legacy CRM task identity protection was weakened'; END IF;
END $$;
-- Simulate a preexisting linked Contact task without its registry entry; the
-- retry must register/reuse it instead of creating a second task.
DELETE FROM public.crm_generated_tasks WHERE deal_id='00000000-0000-4000-8000-000000000201';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','LEAD');
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','QUALIFICATION');
RESET ROLE;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.tasks WHERE crm_deal_id='00000000-0000-4000-8000-000000000201' AND crm_workflow_kind='CONTACT_DISCUSSION') <> 1 THEN
    RAISE EXCEPTION 'preexisting linked Contact task was duplicated';
  END IF;
END $$;
UPDATE public.crm_deals SET workflow_status='APPROVED' WHERE id='00000000-0000-4000-8000-000000000203';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000203','NEGOTIATION');
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000203','WON');
DO $$ DECLARE rejected boolean := false; BEGIN
  BEGIN
    PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000203','LOST');
  EXCEPTION WHEN check_violation THEN rejected := true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'Lost transition without a reason was not rejected'; END IF;
END $$;
RESET ROLE;
UPDATE public.crm_deals SET lost_reason='Synthetic lost reason' WHERE id='00000000-0000-4000-8000-000000000203';
SET ROLE authenticated;
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000203','LOST');
RESET ROLE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id='00000000-0000-4000-8000-000000000204' AND stage='NEGOTIATION') THEN
    RAISE EXCEPTION 'historical Negotiation stage was changed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.tasks'::regclass AND conname='tasks_crm_workflow_kind_check') THEN
    RAISE EXCEPTION 'CRM task kind constraint missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.crm_generated_tasks
                 WHERE deal_id='00000000-0000-4000-8000-000000000206'
                   AND kind='QUOTE_PROPOSAL_DESIGN'
                   AND task_id='00000000-0000-4000-8000-000000000306') THEN
    RAISE EXCEPTION 'migration did not preserve the legacy Design registry mapping';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_schema='public' AND routine_name='create_crm_design_task_for_deal') THEN
    -- The existing source is deliberately not imported into this fixture; this assertion is static in the paired CJS test.
    NULL;
  END IF;
END $$;
-- Reopening is the first permitted opportunity to synchronize the legacy
-- assigned_to value, after which Qualification automation uses that assignee.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000205','LEAD');
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000205','QUALIFICATION');
RESET ROLE;
DO $$ DECLARE task_row public.tasks%ROWTYPE; BEGIN
  SELECT * INTO task_row FROM public.tasks WHERE crm_deal_id='00000000-0000-4000-8000-000000000205'
    AND crm_workflow_kind='CONTACT_DISCUSSION';
  IF NOT FOUND OR task_row.assignee_ids <> ARRAY['00000000-0000-4000-8000-000000000001']::uuid[]
     OR NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id='00000000-0000-4000-8000-000000000205'
                    AND cardinality(assignee_ids)=0 AND assigned_to='00000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'reopened legacy deal did not automate to its existing assignee';
  END IF;
END $$;
BEGIN;
INSERT INTO public.crm_generated_tasks(deal_id,kind,task_id)
VALUES ('00000000-0000-4000-8000-000000000204','QUOTE_PROPOSAL_DESIGN','00000000-0000-4000-8000-000000000301');
INSERT INTO public.tasks(id,title,created_by,crm_deal_id,crm_workflow_kind)
VALUES ('00000000-0000-4000-8000-000000000301','Synthetic existing Design task',
        '00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000204','QUOTE_PROPOSAL_DESIGN');
COMMIT;
`;

const crmSeed = String.raw`
INSERT INTO public.profiles(id,is_active,crm_access) VALUES
 ('00000000-0000-4000-8000-000000000001',true,false),
 ('00000000-0000-4000-8000-000000000002',true,false),
 ('00000000-0000-4000-8000-000000000003',true,true),
 ('00000000-0000-4000-8000-000000000004',false,false);
INSERT INTO auth.users(id,email) SELECT id, 'synthetic-' || id::text || '@example.invalid' FROM public.profiles;
INSERT INTO public.crm_clients(id,name,company) VALUES ('00000000-0000-4000-8000-000000000100','Synthetic Client','Test');
`;

// Extend the same disposable database after CRM Release 1A has run. The four
// critical pre-migration Staging function bodies come from the checked-in
// export fixture. The runtime schema and these two restrictive policies are
// synthetic; the remaining Staging policies are not represented as exact.
const mq20Prerequisites = String.raw`
UPDATE public.profiles SET employee_id = CASE id
  WHEN '00000000-0000-4000-8000-000000000001'::uuid THEN 'MQ-20'
  WHEN '00000000-0000-4000-8000-000000000002'::uuid THEN 'EMP-2'
  WHEN '00000000-0000-4000-8000-000000000003'::uuid THEN 'CRM-ADMIN'
  WHEN '00000000-0000-4000-8000-000000000004'::uuid THEN 'INACTIVE'
  ELSE employee_id END;
INSERT INTO public.profiles(id,employee_id,is_active,crm_access,financial_access)
VALUES ('00000000-0000-4000-8000-000000000005','MQ-20',true,false,false);
ALTER TABLE public.tasks
  ADD COLUMN archived_at timestamptz,
  ADD COLUMN started_at timestamptz,
  ADD COLUMN completed_at timestamptz,
  ADD COLUMN work_state text NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN resume_status text,
  ADD COLUMN waiting_category text,
  ADD COLUMN waiting_related_user_id uuid,
  ADD COLUMN waiting_note text,
  ADD COLUMN waiting_since timestamptz,
  ADD COLUMN blocked_category text,
  ADD COLUMN blocked_related_user_id uuid,
  ADD COLUMN blocked_note text,
  ADD COLUMN blocked_since timestamptz,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
CREATE TABLE public.task_waiting_history(
  id bigserial PRIMARY KEY, task_id uuid NOT NULL, actor_id uuid, category text NOT NULL,
  related_user_id uuid, note text, started_at timestamptz NOT NULL DEFAULT now(), resumed_at timestamptz, resumed_by uuid
);
CREATE TABLE public.task_blocker_history(
  id bigserial PRIMARY KEY, task_id uuid NOT NULL, actor_id uuid, category text NOT NULL,
  related_user_id uuid, note text, created_at timestamptz NOT NULL DEFAULT now(), resolved_at timestamptz, resolved_by uuid
);
CREATE TABLE public.task_activity(
  id bigserial PRIMARY KEY, task_id uuid NOT NULL, actor_id uuid, action text NOT NULL,
  from_status text, to_status text, metadata jsonb NOT NULL DEFAULT '{}'
);
CREATE TABLE public.task_dependencies(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), predecessor_task_id uuid NOT NULL,
  successor_task_id uuid NOT NULL, removed_at timestamptz
);
CREATE OR REPLACE FUNCTION public.is_mq07_design_list(uuid,uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.notify_task_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION public.queue_task_status_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION public.record_task_activity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.task_activity(task_id,actor_id,action,from_status,to_status) VALUES(NEW.id,auth.uid(),'TASK_STATUS_CHANGED',OLD.status,NEW.status);
  END IF;
  IF TG_OP='UPDATE' AND (NEW.assignee_id IS DISTINCT FROM OLD.assignee_id OR NEW.assignee_ids IS DISTINCT FROM OLD.assignee_ids) THEN
    INSERT INTO public.task_activity(task_id,actor_id,action,metadata) VALUES(NEW.id,auth.uid(),'TASK_ASSIGNED',jsonb_build_object('assignee_id',NEW.assignee_id,'assignee_ids',NEW.assignee_ids));
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER notify_task_change_trigger AFTER INSERT OR UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.notify_task_change();
CREATE TRIGGER task_status_notification_trigger AFTER UPDATE OF status ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.queue_task_status_notification();
CREATE TRIGGER task_activity_after_insert AFTER INSERT ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();
CREATE TRIGGER task_activity_after_update AFTER UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();
CREATE TRIGGER task_activity_before_delete BEFORE DELETE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();
CREATE TABLE public.task_lists(id uuid PRIMARY KEY, owner_id uuid);
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY mq20_no_tasks_delete ON public.tasks AS RESTRICTIVE FOR DELETE TO authenticated USING (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_no_tasks_insert ON public.tasks AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_no_tasks_update ON public.tasks AS RESTRICTIVE FOR UPDATE TO authenticated USING (NOT public.is_mq20_profile(auth.uid())) WITH CHECK (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_only_ines_tasks_select ON public.tasks AS RESTRICTIVE FOR SELECT TO authenticated USING ((NOT public.is_mq20_profile(auth.uid())) OR public.is_ines_modani_task(id) OR public.can_view_own_crm_contact_task(id, auth.uid()));
CREATE POLICY mq20_test_task_update ON public.tasks AS PERMISSIVE FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY mq20_no_task_comments_delete ON public.task_comments AS RESTRICTIVE FOR DELETE TO authenticated USING (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_no_task_comments_insert ON public.task_comments AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_no_task_comments_update ON public.task_comments AS RESTRICTIVE FOR UPDATE TO authenticated USING (NOT public.is_mq20_profile(auth.uid())) WITH CHECK (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_only_ines_task_comments_select ON public.task_comments AS RESTRICTIVE FOR SELECT TO authenticated USING ((NOT public.is_mq20_profile(auth.uid())) OR public.is_ines_modani_task(task_id) OR public.crm_is_own_generated_contact_task(task_id, auth.uid()));
CREATE POLICY mq20_test_comments_select ON public.task_comments AS PERMISSIVE FOR SELECT TO authenticated USING (true);
CREATE POLICY mq20_test_comments_insert ON public.task_comments AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);
ALTER TABLE public.task_attachments ENABLE ROW LEVEL SECURITY;
CREATE POLICY mq20_only_ines_task_attachments_select ON public.task_attachments AS RESTRICTIVE FOR SELECT TO authenticated USING ((NOT public.is_mq20_profile(auth.uid())) OR public.is_ines_modani_task(task_id) OR public.crm_is_own_generated_contact_task(task_id, auth.uid()));
CREATE POLICY mq20_test_attachments_select ON public.task_attachments AS PERMISSIVE FOR SELECT TO authenticated USING (true);
ALTER TABLE public.task_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY mq20_no_task_lists_delete ON public.task_lists AS RESTRICTIVE FOR DELETE TO authenticated USING (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_no_task_lists_insert ON public.task_lists AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_no_task_lists_update ON public.task_lists AS RESTRICTIVE FOR UPDATE TO authenticated USING (NOT public.is_mq20_profile(auth.uid())) WITH CHECK (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY mq20_only_ines_task_lists_select ON public.task_lists AS RESTRICTIVE FOR SELECT TO authenticated USING ((NOT public.is_mq20_profile(auth.uid())) OR public.is_ines_modani_task_list(id));

CREATE POLICY mq20_test_task_lists_select ON public.task_lists AS PERMISSIVE FOR SELECT TO authenticated USING (true);
CREATE TRIGGER mq20_view_only_task_comments BEFORE INSERT OR DELETE OR UPDATE ON public.task_comments
  FOR EACH ROW EXECUTE FUNCTION public.enforce_mq20_task_service_boundaries();
CREATE TRIGGER mq20_view_only_task_attachments BEFORE INSERT OR DELETE OR UPDATE ON public.task_attachments
  FOR EACH ROW EXECUTE FUNCTION public.enforce_mq20_task_service_boundaries();
CREATE TRIGGER mq20_view_only_task_dependencies BEFORE INSERT OR DELETE OR UPDATE ON public.task_dependencies
  FOR EACH ROW EXECUTE FUNCTION public.enforce_mq20_task_service_boundaries();
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT,UPDATE ON public.crm_deals,public.tasks TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.task_comments,public.task_attachments,public.task_dependencies TO authenticated;

GRANT SELECT,INSERT,UPDATE,DELETE ON public.task_lists TO authenticated;
GRANT USAGE,SELECT ON SEQUENCE public.task_comments_id_seq TO authenticated;
` + '\n' + productivityValidateCategory + '\n' + taskDependencyBlocked + String.raw`
UPDATE public.crm_deals
   SET title='Synthetic multi-assignee deal', assignee_ids=ARRAY[
       '00000000-0000-4000-8000-000000000001'::uuid,
       '00000000-0000-4000-8000-000000000002'::uuid
   ]
 WHERE title='Single assignment';
`;

const mq20Assertions = String.raw`
SELECT set_config('test.mq20.deal_id', (
  SELECT deal.id::text FROM public.crm_deals deal WHERE deal.title='Synthetic multi-assignee deal' LIMIT 1), false);
SELECT set_config('test.mq20.task_id', (
  SELECT task.id::text FROM public.tasks task JOIN public.crm_deals deal ON deal.id=task.crm_deal_id
   WHERE deal.id=current_setting('test.mq20.deal_id')::uuid AND task.crm_workflow_kind='CONTACT_DISCUSSION' LIMIT 1), false);
DO $$ BEGIN
  IF current_setting('test.mq20.deal_id',true) IS NULL OR current_setting('test.mq20.task_id',true) IS NULL THEN RAISE EXCEPTION 'Synthetic multi-assignee CRM Contact task missing'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.crm_deals WHERE id=current_setting('test.mq20.deal_id')::uuid AND assignee_ids=ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[]) THEN RAISE EXCEPTION 'CRM migration did not preserve the synthetic multi-assignee set'; END IF;
END $$;
INSERT INTO public.tasks(id,title,created_by,status) VALUES ('00000000-0000-4000-8000-000000000901','Synthetic successor','00000000-0000-4000-8000-000000000003','todo');
INSERT INTO public.task_dependencies(predecessor_task_id,successor_task_id) VALUES (current_setting('test.mq20.task_id')::uuid,'00000000-0000-4000-8000-000000000901');
SELECT set_config('test.mq20.notifications_before',(SELECT count(*)::text FROM public.notifications),false);
SELECT set_config('test.mq20.outbox_before',(SELECT count(*)::text FROM public.task_email_outbox),false);
INSERT INTO public.task_comments(task_id,user_id,content) VALUES(current_setting('test.mq20.task_id')::uuid,'00000000-0000-4000-8000-000000000001','Synthetic readable comment');
INSERT INTO public.task_attachments(task_id,user_id,file_url,file_name) VALUES(current_setting('test.mq20.task_id')::uuid,'00000000-0000-4000-8000-000000000001','synthetic://attachment','synthetic.txt');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ BEGIN
 IF (SELECT count(*) FROM public.task_comments WHERE task_id=current_setting('test.mq20.task_id')::uuid)<>1 THEN RAISE EXCEPTION 'MQ-20 primary assignee lost permitted Contact comment visibility'; END IF;
 IF (SELECT count(*) FROM public.task_attachments WHERE task_id=current_setting('test.mq20.task_id')::uuid)<>1 THEN RAISE EXCEPTION 'MQ-20 primary assignee lost permitted Contact attachment visibility'; END IF;
END $$;
SELECT public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'START');
SELECT public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'START');
SELECT public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'WAIT','CLIENT','Synthetic wait');
SELECT public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'BLOCK','OTHER','Synthetic block');
SELECT public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'RESUME');
SELECT public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'COMPLETE');
DO $$ DECLARE denied boolean:=false; BEGIN
  UPDATE public.tasks SET title='forged MQ-20 task write' WHERE id=current_setting('test.mq20.task_id')::uuid;
  IF FOUND THEN RAISE EXCEPTION 'Restrictive task RLS allowed direct MQ-20 write'; END IF;
  BEGIN INSERT INTO public.task_comments(task_id,user_id,content) VALUES(current_setting('test.mq20.task_id')::uuid,auth.uid(),'forged child write');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Restrictive child-row RLS allowed direct MQ-20 comment write'; END IF;
  denied:=false;
  BEGIN INSERT INTO public.task_attachments(task_id,user_id,file_url,file_name) VALUES(current_setting('test.mq20.task_id')::uuid,auth.uid(),'synthetic://no-upload','synthetic.txt');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'MQ-20 task guard allowed direct attachment registration'; END IF;
  denied:=false;
  BEGIN INSERT INTO public.task_dependencies(predecessor_task_id,successor_task_id) VALUES(current_setting('test.mq20.task_id')::uuid,'00000000-0000-4000-8000-000000000901');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'MQ-20 task guard allowed direct dependency mutation'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
DO $$ BEGIN
 IF (SELECT count(*) FROM public.task_comments WHERE task_id=current_setting('test.mq20.task_id')::uuid)<>1 THEN RAISE EXCEPTION 'MQ-20 secondary assignee lost permitted Contact comment visibility'; END IF;
 IF (SELECT count(*) FROM public.task_attachments WHERE task_id=current_setting('test.mq20.task_id')::uuid)<>1 THEN RAISE EXCEPTION 'MQ-20 secondary assignee lost permitted Contact attachment visibility'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
RESET ROLE;
DO $$ DECLARE denied boolean:=false; BEGIN
  IF (SELECT count(*) FROM public.notifications)<>current_setting('test.mq20.notifications_before')::integer
     OR (SELECT count(*) FROM public.task_email_outbox)<>current_setting('test.mq20.outbox_before')::integer THEN RAISE EXCEPTION 'Scoped task actions emitted notification/outbox rows'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.tasks WHERE id='00000000-0000-4000-8000-000000000901' AND status='todo') THEN RAISE EXCEPTION 'Scoped completion activated its successor'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.task_activity WHERE task_id=current_setting('test.mq20.task_id')::uuid) THEN RAISE EXCEPTION 'Scoped task actions did not preserve activity logging'; END IF;
END $$;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
UPDATE public.crm_deals SET assigned_to='00000000-0000-4000-8000-000000000001', assignee_ids=ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000005']::uuid[] WHERE id=current_setting('test.mq20.deal_id')::uuid;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.tasks WHERE id=current_setting('test.mq20.task_id')::uuid AND assignee_ids=ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000005']::uuid[] AND visible_to=ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000005']::uuid[]) THEN RAISE EXCEPTION 'Deal-to-task multi-assignee synchronization failed'; END IF;
END $$;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
UPDATE public.crm_deals SET assigned_to='00000000-0000-4000-8000-000000000002', assignee_ids=ARRAY['00000000-0000-4000-8000-000000000002']::uuid[] WHERE id=current_setting('test.mq20.deal_id')::uuid;
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'START'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Removed CRM assignee retained scoped execution access'; END IF;
END $$;
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
UPDATE public.crm_deals SET assigned_to='00000000-0000-4000-8000-000000000001', assignee_ids=ARRAY['00000000-0000-4000-8000-000000000001']::uuid[], lost_reason='Synthetic MQ-20 test loss' WHERE id=current_setting('test.mq20.deal_id')::uuid;
SELECT public.change_crm_deal_stage(current_setting('test.mq20.deal_id')::uuid,'LOST');
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'START'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Lost CRM deal remained executable'; END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','',false);
UPDATE public.tasks SET archived_at=now() WHERE id=current_setting('test.mq20.task_id')::uuid;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.execute_crm_contact_discussion_task(current_setting('test.mq20.task_id')::uuid,'START'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Archived Contact task remained executable'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_function_privilege('anon','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE')
    OR has_function_privilege('service_role','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Scoped RPC grants do not match expected authenticated-only policy'; END IF;
 IF has_function_privilege('authenticated','hrsys_private.valid_mq20_task_context(uuid,text,text)','EXECUTE')
    OR has_schema_privilege('authenticated','hrsys_private','USAGE') THEN RAISE EXCEPTION 'Private context helper is exposed'; END IF;
END $$;
`;

let dockerContainer;
const run = (binary, args, options = {}) => {
  if (dockerMode) return postgresDocker.run(binary, args, dockerContainer);
  const result = childProcess.spawnSync(binary, args, { encoding: 'utf8', windowsHide: true, ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${path.basename(binary)} failed (${result.status}):\n${result.stdout || ''}\n${result.stderr || ''}`);
  return result.stdout || '';
};
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

(async () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hrsys-crm-discussion-pg-'));
  const dataDir = path.join(tempRoot, 'data');
  const logFile = path.join(tempRoot, 'postgres.log');
  const sqlFile = path.join(tempRoot, 'runtime.sql');
  const reservation = net.createServer();
  let port;
  let serverStarted = false;
  let serverProcess;
  let logFd;
  try {
    if (dockerMode) {
      const disposable = await postgresDocker.start('hrsys-pg17-crm-three-migrations');
      dockerContainer = disposable.name;
      serverStarted = true;
      port = 5432;
      console.log(`Disposable Docker PostgreSQL ${disposable.version} (network=none; no published port).`);
    } else {
      await new Promise((resolve, reject) => reservation.listen(0, '127.0.0.1', resolve).once('error', reject));
      port = reservation.address().port;
      await new Promise(resolve => reservation.close(resolve));
      run(initdb, ['-D', dataDir, '-U', 'postgres', '--auth=trust', '--no-locale', '-E', 'UTF8']);
      logFd = fs.openSync(logFile, 'wx');
      serverProcess = childProcess.spawn(postgres, ['-D', dataDir, '-h', '127.0.0.1', '-p', String(port), '-c', 'listen_addresses=127.0.0.1'], {
        windowsHide: true, stdio: ['ignore', logFd, logFd]
      });
      serverProcess.once('error', error => { serverProcess.spawnError = error; });
      let ready = false;
      for (let attempt = 0; attempt < 80; attempt += 1) {
        if (serverProcess.spawnError || serverProcess.exitCode !== null) {
          throw serverProcess.spawnError || new Error(`Disposable PostgreSQL exited early. Log: ${logFile}`);
        }
        const readiness = childProcess.spawnSync(pgIsReady, ['-h', '127.0.0.1', '-p', String(port), '-U', 'postgres'], { encoding: 'utf8', windowsHide: true });
        if (readiness.status === 0) { ready = true; break; }
        await delay(250);
      }
      if (!ready) throw new Error(`Disposable PostgreSQL did not become ready. Log: ${logFile}`);
      serverStarted = true;
    }
    const serverVersion = run(psql, ['-X', '-A', '-t', '-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres', '-c', 'SHOW server_version']).trim();
    if (!dockerMode) console.log(`Disposable PostgreSQL runtime: ${serverVersion} (localhost-only)`);
    const baselineSql = [baseline, taskCreate, dealRead, stageChange].join('\n\n');
    const migrationFile = path.join(tempRoot, 'migration.sql');
    const crmSeedFile = path.join(tempRoot, 'crm-seed.sql');
    const assertionsFile = path.join(tempRoot, 'assertions.sql');
    const mq20PrerequisitesFile = path.join(tempRoot, 'mq20-prerequisites.sql');
    const mq20MigrationFile = path.join(tempRoot, 'mq20-migration.sql');
    const mq20AssertionsFile = path.join(tempRoot, 'mq20-assertions.sql');
    const compatibilityMigrationFile = path.join(tempRoot, 'compatibility-migration.sql');
    fs.writeFileSync(sqlFile, baselineSql, 'utf8');
    fs.writeFileSync(migrationFile, migration, 'utf8');
    fs.writeFileSync(crmSeedFile, crmSeed, 'utf8');
    fs.writeFileSync(assertionsFile, assertions, 'utf8');
    fs.writeFileSync(mq20PrerequisitesFile, mq20Prerequisites, 'utf8');
    fs.writeFileSync(mq20MigrationFile, mq20Migration, 'utf8');
    fs.writeFileSync(mq20AssertionsFile, mq20Assertions, 'utf8');
    fs.writeFileSync(compatibilityMigrationFile, compatibilityMigration, 'utf8');
    const psqlArgs = ['-X', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres'];
    run(psql, [...psqlArgs, '-f', sqlFile]);
    run(psql, [...psqlArgs, '-f', crmSeedFile]);
    const stagingFunctionHashes = {
      'is_mq20_profile(uuid)': '873a1aecadf1d0fec3fceca822adf6b7',
      'enforce_mq20_task_service_boundaries()': '65b527d869470c3c0dc5261da011ba30',
      'protect_crm_generated_task_identity()': 'f87b9f595740451bae82009de5243555',
      'protect_task_access_fields()': '37bccb413df3d923abb1359d26163835'
    };
    const fingerprintMismatches = [];
    for (const [signature, expectedHash] of Object.entries(stagingFunctionHashes)) {
      const actualHash = run(psql, [...psqlArgs, '-A', '-t', '-c', `SELECT md5(pg_get_functiondef('public.${signature}'::regprocedure))`]).trim();
      if (actualHash !== expectedHash) fingerprintMismatches.push(`${signature}: expected ${expectedHash}, got ${actualHash}`);
      else console.log(`STAGING FINGERPRINT PASS ${signature}: ${actualHash}`);
    }
    assert.equal(fingerprintMismatches.length, 0, `Staging function fixture fingerprint mismatch(es):\n${fingerprintMismatches.join('\n')}`);
    const isMq20Acl = JSON.parse(run(psql, [...psqlArgs, '-A', '-t', '-c', `
      SELECT jsonb_agg(CASE acl.grantee WHEN 0 THEN 'PUBLIC' ELSE grantee.rolname END ORDER BY CASE acl.grantee WHEN 0 THEN 'PUBLIC' ELSE grantee.rolname END)::text
        FROM pg_proc routine
        CROSS JOIN LATERAL aclexplode(COALESCE(routine.proacl, acldefault('f', routine.proowner))) acl
        LEFT JOIN pg_roles grantee ON grantee.oid=acl.grantee
       WHERE routine.oid='public.is_mq20_profile(uuid)'::regprocedure
         AND acl.privilege_type='EXECUTE' AND NOT acl.is_grantable`]).trim());
    assert.deepEqual(isMq20Acl, ['PUBLIC', 'anon', 'authenticated', 'postgres', 'service_role'], 'is_mq20_profile execution ACL differs from the supplied Staging assignment-security export');
    console.log('Staging is_mq20_profile execution ACL matches the supplied assignment-security export.');
    run(psql, [...psqlArgs, '-f', migrationFile]);
    run(psql, [...psqlArgs, '-f', mq20PrerequisitesFile]);
    const legacyMq20PolicyCheck = run(psql, [...psqlArgs, '-A', '-t', '-c', `
      SELECT policyname || '|' || COALESCE(qual, '') || '|' || COALESCE(with_check, '') FROM pg_policies
       WHERE schemaname='public'
         AND policyname IN ('mq20_no_tasks_update','mq20_no_task_comments_insert') ORDER BY policyname`]).trim();
    assert.equal(legacyMq20PolicyCheck.split(/\r?\n/).length, 2, 'Verified restrictive MQ-20 task/comment policies are absent');
    assert.ok(legacyMq20PolicyCheck.split(/\r?\n/).every(line => line.includes('NOT is_mq20_profile(auth.uid())')), 'Restrictive MQ-20 policies no longer deny the profile');
    console.log('Staging function fingerprints and restrictive task/comment policy expressions match the supplied exports.');
    run(psql, [...psqlArgs, '-f', mq20MigrationFile]);
    for (const signature of [
      'public.enforce_deal_workflow_transition()',
      'public.can_view_own_crm_contact_task(uuid,uuid)',
      'public.crm_is_own_generated_contact_task(uuid,uuid)',
      'public.decide_crm_design_task_approval(uuid,text,text)',
      'public.queue_task_notification(uuid,uuid,text,text)'
    ]) {
      const fingerprint = run(psql, [...psqlArgs, '-A', '-t', '-c', `SELECT md5(pg_get_functiondef('${signature}'::regprocedure))`]).trim();
      console.log(`PRE-COMPATIBILITY ${signature}: ${fingerprint}`);
    }
    run(psql, [...psqlArgs, '-f', compatibilityMigrationFile]);
    const protectedMq20Acl = run(psql, [...psqlArgs, '-A', '-t', '-c', `
      SELECT EXISTS (SELECT 1 FROM pg_proc routine CROSS JOIN LATERAL aclexplode(COALESCE(routine.proacl, acldefault('f',routine.proowner))) acl WHERE routine.oid='public.is_mq20_profile(uuid)'::regprocedure AND acl.grantee=0 AND acl.privilege_type='EXECUTE')::text
        || '|' || has_function_privilege('anon','public.is_mq20_profile(uuid)','EXECUTE')::text
        || '|' || has_function_privilege('authenticated','public.is_mq20_profile(uuid)','EXECUTE')::text
        || '|' || has_function_privilege('service_role','public.is_mq20_profile(uuid)','EXECUTE')::text
        || '|' || has_function_privilege('postgres','public.is_mq20_profile(uuid)','EXECUTE')::text
        || '|' || EXISTS (SELECT 1 FROM pg_proc routine CROSS JOIN LATERAL aclexplode(COALESCE(routine.proacl, acldefault('f',routine.proowner))) acl WHERE routine.oid='public.is_mq20_current_user()'::regprocedure AND acl.grantee=0 AND acl.privilege_type='EXECUTE')::text
        || '|' || has_function_privilege('anon','public.is_mq20_current_user()','EXECUTE')::text
        || '|' || has_function_privilege('authenticated','public.is_mq20_current_user()','EXECUTE')::text
        || '|' || has_function_privilege('service_role','public.is_mq20_current_user()','EXECUTE')::text`]).trim();
    assert.equal(protectedMq20Acl, 'false|false|false|true|true|false|false|true|false', 'MQ-20 helper grants do not limit membership checks to the current authenticated user');
    const mq20ProbeChecks = `SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false); DO $probe$ DECLARE blocked boolean := false; BEGIN BEGIN PERFORM public.is_mq20_profile('00000000-0000-4000-8000-000000000002'); EXCEPTION WHEN insufficient_privilege THEN blocked := true; END; IF NOT blocked THEN RAISE EXCEPTION 'Authenticated role probed another employee through is_mq20_profile'; END IF; IF public.is_mq20_current_user() IS DISTINCT FROM true THEN RAISE EXCEPTION 'MQ-20 authenticated self-check failed'; END IF; END $probe$; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false); DO $self$ BEGIN IF public.is_mq20_current_user() IS DISTINCT FROM false THEN RAISE EXCEPTION 'Non-MQ-20 authenticated self-check was incorrect'; END IF; END $self$; RESET ROLE; SET ROLE anon; DO $anon$ DECLARE blocked boolean := false; BEGIN BEGIN PERFORM public.is_mq20_profile('00000000-0000-4000-8000-000000000001'); EXCEPTION WHEN insufficient_privilege THEN blocked := true; END; IF NOT blocked THEN RAISE EXCEPTION 'Anonymous role probed MQ-20 membership'; END IF; END $anon$; RESET ROLE;`;
    run(psql, [...psqlArgs, '-c', mq20ProbeChecks]);
    console.log('PASS: arbitrary-UUID helper probing denied to anon/authenticated; authenticated current-user helper works.');
    run(psql, [...psqlArgs, '-f', assertionsFile]);
    run(psql, [...psqlArgs, '-f', mq20AssertionsFile]);
    const negotiationAllowedOutput = run(psql, [...psqlArgs, '-A', '-t', '-c', `
      INSERT INTO public.crm_deals(id,client_id,title,stage,assigned_to,created_by,workflow_status)
      VALUES ('00000000-0000-4000-8000-000000000299','00000000-0000-4000-8000-000000000100','Compatibility Negotiation','NEGOTIATION','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','APPROVED')
      ON CONFLICT (id) DO NOTHING;
      SELECT count(*) FROM public.crm_deals WHERE id='00000000-0000-4000-8000-000000000299' AND stage='NEGOTIATION'`]).trim();
    const negotiationAllowed = negotiationAllowedOutput.split(/\r?\n/).pop();
    assert.equal(negotiationAllowed, '1', 'Compatibility migration did not preserve a first-class Negotiation stage.');
    console.log('PostgreSQL disposable runtime assertions passed: CRM migration 1, MQ-20 migration 2, and Staging compatibility migration 3 in dependency order; exported Staging guard functions, synthetic schema, and limited RLS overlays.');
  } finally {
    if (serverStarted) {
      if (dockerMode) {
        postgresDocker.stop(dockerContainer);
        dockerContainer = undefined;
        serverStarted = false;
      } else {
        const stopped = childProcess.spawnSync(pgCtl, ['-D', dataDir, '-m', 'fast', '-w', 'stop'], { encoding: 'utf8', windowsHide: true });
        if (stopped.status !== 0) console.error('Temporary PostgreSQL cluster did not stop cleanly; data directory retained:', tempRoot);
        else serverStarted = false;
      }
    }
    if (!serverStarted && (!serverProcess || serverProcess.exitCode !== null || !fs.existsSync(path.join(dataDir, 'postmaster.pid')))) {
      try { fs.rmSync(tempRoot, { recursive: true, force: true }); }
      catch (error) { console.error('Could not remove only the test-created temporary directory:', error.message); }
    }
    if (logFd !== undefined) fs.closeSync(logFd);
  }
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
