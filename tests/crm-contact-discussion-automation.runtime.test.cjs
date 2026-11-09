/* eslint-env node */
// Disposable PostgreSQL behavior test. It starts only a new temp cluster bound
// to 127.0.0.1 and imports the tracked source functions plus synthetic schema/data.
const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');

const root = path.join(__dirname, '..');
const pgBin = process.env.PG_BIN || 'C:\\Program Files\\PostgreSQL\\18\\bin';
const initdb = path.join(pgBin, 'initdb.exe');
const pgCtl = path.join(pgBin, 'pg_ctl.exe');
const postgres = path.join(pgBin, 'postgres.exe');
const psql = path.join(pgBin, 'psql.exe');
const pgIsReady = path.join(pgBin, 'pg_isready.exe');
for (const binary of [initdb, pgCtl, postgres, psql, pgIsReady]) assert.ok(fs.existsSync(binary), `Missing disposable PostgreSQL utility: ${binary}`);

const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const extractFunction = (source, name) => {
  const expression = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\n\\$\\$;`, 'i');
  const match = source.match(expression);
  assert.ok(match, `Could not extract tracked function ${name}`);
  return match[0];
};

const shared = read('supabase/migrations/20260917090000_shared_business_logic_services.sql');
const dealBackend = read('supabase/migrations/20260930102000_deal_backend_services.sql');
const migration = read('supabase/migrations/20261109100000_crm_contact_discussion_automation.sql');
const taskCreate = extractFunction(shared, 'create_task_secure');
const stageChange = extractFunction(shared, 'change_crm_deal_stage');
const dealRead = extractFunction(dealBackend, 'get_crm_deal_secure');

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
  id uuid PRIMARY KEY, is_active boolean DEFAULT true,
  crm_access boolean NOT NULL DEFAULT false, financial_access boolean NOT NULL DEFAULT false
);
CREATE TABLE public.crm_clients (id uuid PRIMARY KEY, name text, company text);
CREATE TABLE public.crm_deals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), client_id uuid, title text NOT NULL,
  amount numeric DEFAULT 0, stage text NOT NULL DEFAULT 'LEAD', closing_date date,
  assigned_to uuid, event_type text, first_contact_date date, contact_method text,
  lead_source text, technical_description text, created_by uuid,
  workflow_status text DEFAULT 'NOT_STARTED', approval_type text, design_task_id uuid,
  proposal_sent_at timestamptz,
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
  notify_via_email boolean DEFAULT false, crm_deal_id uuid, crm_workflow_kind text,
  CONSTRAINT tasks_crm_workflow_kind_check CHECK (crm_workflow_kind IS NULL OR crm_workflow_kind='QUOTE_PROPOSAL_DESIGN')
);
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
`;

const assertions = String.raw`
INSERT INTO public.profiles(id,is_active,crm_access) VALUES
 ('00000000-0000-4000-8000-000000000001',true,false),
 ('00000000-0000-4000-8000-000000000002',true,false),
 ('00000000-0000-4000-8000-000000000003',true,true),
 ('00000000-0000-4000-8000-000000000004',false,false);
INSERT INTO public.crm_clients(id,name,company) VALUES ('00000000-0000-4000-8000-000000000100','Synthetic Client','Test');
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
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
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
     OR task_row.created_by <> auth.uid() THEN RAISE EXCEPTION 'single assignee or actor separation failed'; END IF;
  PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','QUALIFICATION');
  PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','LEAD');
  PERFORM public.change_crm_deal_stage('00000000-0000-4000-8000-000000000201','QUALIFICATION');
  SELECT count(*) INTO task_count FROM public.tasks WHERE crm_deal_id='00000000-0000-4000-8000-000000000201' AND crm_workflow_kind='CONTACT_DISCUSSION';
  IF task_count <> 1 THEN RAISE EXCEPTION 'retry/re-entry created a duplicate task'; END IF;
END $$;

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
SELECT public.change_crm_deal_stage('00000000-0000-4000-8000-000000000203','LOST');
RESET ROLE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id='00000000-0000-4000-8000-000000000204' AND stage='NEGOTIATION') THEN
    RAISE EXCEPTION 'historical Negotiation stage was changed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.tasks'::regclass AND conname='tasks_crm_workflow_kind_check') THEN
    RAISE EXCEPTION 'CRM task kind constraint missing';
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
  IF NOT FOUND OR task_row.assignee_ids <> ARRAY['00000000-0000-4000-8000-000000000001']::uuid[] THEN
    RAISE EXCEPTION 'reopened legacy deal did not automate to its existing assignee';
  END IF;
END $$;
INSERT INTO public.tasks(id,title,created_by,crm_deal_id,crm_workflow_kind)
VALUES ('00000000-0000-4000-8000-000000000301','Synthetic existing Design task',
        '00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000204','QUOTE_PROPOSAL_DESIGN');
`;

const run = (binary, args, options = {}) => {
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
    const serverVersion = run(psql, ['-X', '-A', '-t', '-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres', '-c', 'SHOW server_version']).trim();
    console.log(`Disposable PostgreSQL runtime: ${serverVersion} (localhost-only)`);
    fs.writeFileSync(sqlFile, [baseline, taskCreate, dealRead, stageChange, migration, assertions].join('\n\n'), 'utf8');
    run(psql, ['-X', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres', '-f', sqlFile]);
    console.log('PostgreSQL disposable runtime assertions passed (synthetic users/tasks only).');
  } finally {
    if (serverStarted) {
      const stopped = childProcess.spawnSync(pgCtl, ['-D', dataDir, '-m', 'fast', '-w', 'stop'], { encoding: 'utf8', windowsHide: true });
      if (stopped.status !== 0) console.error('Temporary PostgreSQL cluster did not stop cleanly; data directory retained:', tempRoot);
      else serverStarted = false;
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
