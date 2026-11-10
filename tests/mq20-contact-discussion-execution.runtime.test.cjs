/* Disposable PostgreSQL behavior test. Synthetic data only; localhost temp cluster. */
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const postgresDocker = require('./helpers/postgres-docker-runtime.cjs');

const root = path.join(__dirname, '..');
const dockerMode = process.env.HRSYS_PG_DOCKER === '1';
const pgBin = process.env.PG_BIN || 'C:\\Program Files\\PostgreSQL\\18\\bin';
const bin = name => path.join(pgBin, `${name}.exe`);
if (!dockerMode) for (const name of ['initdb', 'pg_ctl', 'postgres', 'psql', 'pg_isready']) assert.ok(fs.existsSync(bin(name)), `Missing PostgreSQL utility ${name}`);
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261109110000_mq20_contact_discussion_execution.sql'), 'utf8');
const crmMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20261109100000_crm_contact_discussion_automation.sql'), 'utf8');
const syncFunction = crmMigration.match(/CREATE OR REPLACE FUNCTION public\.sync_crm_deal_assignees\([\s\S]*?\n\$\$;/)?.[0];
assert.ok(syncFunction, 'Tracked CRM assignee normalizer must be present.');

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
CREATE TABLE auth.users(id uuid PRIMARY KEY, email text);
CREATE TABLE public.profiles(id uuid PRIMARY KEY, employee_id text, is_active boolean DEFAULT true, crm_access boolean DEFAULT false);
CREATE TABLE public.crm_deals(id uuid PRIMARY KEY, stage text NOT NULL, assigned_to uuid, assignee_ids uuid[] NOT NULL DEFAULT '{}');
CREATE TABLE public.tasks(
 id uuid PRIMARY KEY, title text NOT NULL, created_by uuid NOT NULL, assignee_id uuid, assignee_ids uuid[] NOT NULL DEFAULT '{}',
 visible_to uuid[] NOT NULL DEFAULT '{}', supervisor_id uuid, project_id uuid, parent_task_id uuid,
 visibility text, watchers uuid[] DEFAULT '{}', task_list_id uuid, crm_deal_id uuid, crm_workflow_kind text,
 archived_at timestamptz, status text NOT NULL DEFAULT 'todo', started_at timestamptz, completed_at timestamptz,
 work_state text NOT NULL DEFAULT 'ACTIVE', resume_status text, waiting_category text, waiting_related_user_id uuid,
 waiting_note text, waiting_since timestamptz, blocked_category text, blocked_related_user_id uuid,
 blocked_note text, blocked_since timestamptz, updated_at timestamptz DEFAULT now()
);
CREATE TABLE public.crm_generated_tasks(
 deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('CONTACT_DISCUSSION','QUOTE_PROPOSAL_DESIGN')),
 task_id uuid NOT NULL UNIQUE REFERENCES public.tasks(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
 PRIMARY KEY(deal_id,kind)
);
ALTER TABLE public.crm_generated_tasks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crm_generated_tasks FROM PUBLIC,anon,authenticated;
CREATE TABLE public.task_waiting_history(id bigserial PRIMARY KEY, task_id uuid, actor_id uuid, category text, related_user_id uuid, note text, started_at timestamptz, resumed_at timestamptz, resumed_by uuid);
CREATE TABLE public.task_blocker_history(id bigserial PRIMARY KEY, task_id uuid, actor_id uuid, category text, related_user_id uuid, note text, created_at timestamptz, resolved_at timestamptz, resolved_by uuid);
CREATE TABLE public.task_activity(id bigserial PRIMARY KEY, task_id uuid, actor_id uuid, action text, from_status text, to_status text, metadata jsonb DEFAULT '{}');
CREATE TABLE public.task_dependencies(predecessor_task_id uuid, successor_task_id uuid, PRIMARY KEY(predecessor_task_id,successor_task_id));
CREATE TABLE public.notifications(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid, message text, event_type text, task_id uuid, actor_id uuid, action_url text, metadata jsonb);
CREATE TABLE public.task_email_outbox(id bigserial PRIMARY KEY, notification_id uuid, task_id uuid, recipient_id uuid, recipient_email text, subject text, message text, action_url text, always_send boolean, context_type text, details jsonb);
CREATE OR REPLACE FUNCTION public.can_access_crm(uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT COALESCE((SELECT crm_access FROM public.profiles WHERE id=$1),false) $$;
CREATE OR REPLACE FUNCTION public.is_mq20_profile(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user_id AND upper(btrim(coalesce(employee_id,'')))='MQ-20' AND is_active IS DISTINCT FROM false) $$;
CREATE OR REPLACE FUNCTION public.is_mq07_design_list(uuid,uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.is_task_admin(uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.productivity_validate_category(p_category text,p_blocked boolean) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_category IN ('CLIENT','OTHER') $$;
CREATE OR REPLACE FUNCTION public.task_dependency_blocked(uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
CREATE OR REPLACE FUNCTION public.email_profile_name(uuid) RETURNS text LANGUAGE sql STABLE AS $$ SELECT 'Synthetic'::text $$;
CREATE OR REPLACE FUNCTION public.queue_task_notification(uuid,uuid,text,text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN INSERT INTO public.notifications(user_id,message,event_type,task_id) VALUES($2,$4,$3,$1); END $$;
CREATE OR REPLACE FUNCTION public.enforce_mq20_task_service_boundaries() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE caller_id uuid := auth.uid(); BEGIN
 IF caller_id IS NULL OR NOT public.is_mq20_profile(caller_id) THEN IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW; END IF;
 IF TG_TABLE_NAME='tasks' AND TG_OP='INSERT' AND NEW.created_by=caller_id AND NEW.assignee_id=caller_id
   AND caller_id=ANY(COALESCE(NEW.assignee_ids,'{}'::uuid[])) AND NEW.crm_workflow_kind='CONTACT_DISCUSSION'
   AND EXISTS(SELECT 1 FROM public.crm_generated_tasks g WHERE g.task_id=NEW.id AND g.deal_id=NEW.crm_deal_id AND g.kind='CONTACT_DISCUSSION') THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'MQ-20 task access is view-only' USING ERRCODE='42501'; END $$;
CREATE OR REPLACE FUNCTION public.protect_task_access_fields() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN IF auth.uid() IS NULL OR public.is_task_admin(auth.uid()) THEN RETURN NEW; END IF;
 IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN RAISE EXCEPTION 'The task creator cannot be changed' USING ERRCODE='42501'; END IF;
 IF auth.uid()<>OLD.created_by AND (NEW.assignee_id IS DISTINCT FROM OLD.assignee_id OR NEW.supervisor_id IS DISTINCT FROM OLD.supervisor_id
 OR NEW.project_id IS DISTINCT FROM OLD.project_id OR NEW.parent_task_id IS DISTINCT FROM OLD.parent_task_id OR NEW.visibility IS DISTINCT FROM OLD.visibility
 OR NEW.visible_to IS DISTINCT FROM OLD.visible_to OR NEW.watchers IS DISTINCT FROM OLD.watchers) THEN RAISE EXCEPTION 'Only the task creator can change task access' USING ERRCODE='42501'; END IF; RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION public.protect_crm_generated_task_identity() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN IF TG_OP='UPDATE' THEN IF NEW.crm_deal_id IS DISTINCT FROM OLD.crm_deal_id OR NEW.crm_workflow_kind IS DISTINCT FROM OLD.crm_workflow_kind THEN RAISE EXCEPTION 'CRM task identity cannot be changed' USING ERRCODE='42501'; END IF;
 IF NEW.crm_workflow_kind IN ('CONTACT_DISCUSSION','QUOTE_PROPOSAL_DESIGN') AND NEW.status IS DISTINCT FROM OLD.status AND lower(btrim(NEW.status)) IN ('pending approval','approved','rejected') THEN RAISE EXCEPTION 'CRM task approval states are retired' USING ERRCODE='23514'; END IF; RETURN NEW; END IF;
 IF NEW.crm_deal_id IS NOT NULL OR NEW.crm_workflow_kind IS NOT NULL THEN IF NOT EXISTS(SELECT 1 FROM public.crm_generated_tasks WHERE task_id=NEW.id AND deal_id=NEW.crm_deal_id AND kind=NEW.crm_workflow_kind) THEN RAISE EXCEPTION 'CRM tasks must be generated by CRM workflow' USING ERRCODE='42501'; END IF; END IF; RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION public.notify_task_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION public.queue_task_status_notification() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN RETURN NEW; END $$;
CREATE OR REPLACE FUNCTION public.record_task_activity() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN INSERT INTO public.task_activity(task_id,actor_id,action,from_status,to_status) VALUES(NEW.id,auth.uid(),'TASK_STATUS_CHANGED',OLD.status,NEW.status); END IF; RETURN NEW; END $$;
`;
const triggers = String.raw`
` + syncFunction + String.raw`
CREATE TRIGGER crm_deal_assignees_sync BEFORE INSERT OR UPDATE OF assigned_to,assignee_ids ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION public.sync_crm_deal_assignees();
CREATE TRIGGER mq20_task_service_view_only BEFORE INSERT OR UPDATE OR DELETE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.enforce_mq20_task_service_boundaries();
CREATE TRIGGER protect_crm_generated_task_identity BEFORE INSERT OR UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.protect_crm_generated_task_identity();
CREATE TRIGGER protect_task_access_fields_trigger BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.protect_task_access_fields();
CREATE TRIGGER notify_task_change_trigger AFTER INSERT OR UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.notify_task_change();
CREATE TRIGGER task_status_notification_trigger AFTER UPDATE OF status ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.queue_task_status_notification();
CREATE TRIGGER task_activity_after_update AFTER UPDATE OF status,assignee_id,assignee_ids ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY mq20_no_tasks_update ON public.tasks AS RESTRICTIVE FOR UPDATE TO authenticated USING (NOT public.is_mq20_profile(auth.uid())) WITH CHECK (NOT public.is_mq20_profile(auth.uid()));
CREATE POLICY test_task_update ON public.tasks AS PERMISSIVE FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, UPDATE ON public.crm_deals TO authenticated;
GRANT SELECT, UPDATE ON public.tasks TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_mq20_profile(uuid), public.can_access_crm(uuid), public.is_task_admin(uuid) TO authenticated;
`;
const assertions = String.raw`
INSERT INTO public.profiles(id,employee_id,is_active,crm_access) VALUES
 ('00000000-0000-4000-8000-000000000001','MQ-20',true,false),
 ('00000000-0000-4000-8000-000000000002','EMP-2',true,false),
 ('00000000-0000-4000-8000-000000000003','CRM-ADMIN',true,true),
 ('00000000-0000-4000-8000-000000000004','MQ-20',true,false),
 ('00000000-0000-4000-8000-000000000005','EMP-5',true,false),
 ('00000000-0000-4000-8000-000000000006','MQ-20',true,false);
INSERT INTO auth.users(id,email) SELECT id,'synthetic@example.invalid' FROM public.profiles;
INSERT INTO public.crm_deals(id,stage,assigned_to,assignee_ids) VALUES
 ('10000000-0000-4000-8000-000000000001','QUALIFICATION','00000000-0000-4000-8000-000000000001',ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[]);
BEGIN;
INSERT INTO public.crm_generated_tasks VALUES ('10000000-0000-4000-8000-000000000001','CONTACT_DISCUSSION','20000000-0000-4000-8000-000000000001');
INSERT INTO public.tasks(id,title,created_by,assignee_id,assignee_ids,visible_to,crm_deal_id,crm_workflow_kind)
VALUES ('20000000-0000-4000-8000-000000000001','Synthetic Contact task','00000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001',
 ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[],
 ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[],
 '10000000-0000-4000-8000-000000000001','CONTACT_DISCUSSION');
COMMIT;
INSERT INTO public.tasks(id,title,created_by,status) VALUES ('20000000-0000-4000-8000-000000000009','Unrelated synthetic task','00000000-0000-4000-8000-000000000003','todo');
INSERT INTO public.tasks(id,title,created_by,status) VALUES ('20000000-0000-4000-8000-000000000010','Synthetic successor task','00000000-0000-4000-8000-000000000003','todo');
INSERT INTO public.task_dependencies VALUES ('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000010');
CREATE TABLE public.mq20_test_expected_counts AS SELECT (SELECT count(*) FROM public.notifications) notifications, (SELECT count(*) FROM public.task_email_outbox) outbox;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SELECT public.execute_crm_contact_discussion_task('20000000-0000-4000-8000-000000000001','START');
SELECT public.execute_crm_contact_discussion_task('20000000-0000-4000-8000-000000000001','WAIT','CLIENT','Synthetic wait');
SELECT public.execute_crm_contact_discussion_task('20000000-0000-4000-8000-000000000001','BLOCK','OTHER','Synthetic block');
SELECT public.execute_crm_contact_discussion_task('20000000-0000-4000-8000-000000000001','RESUME');
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.notifications)<>(SELECT notifications FROM public.mq20_test_expected_counts) OR (SELECT count(*) FROM public.task_email_outbox)<>(SELECT outbox FROM public.mq20_test_expected_counts) THEN RAISE EXCEPTION 'Scoped MQ-20 execution emitted notification/outbox rows'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.tasks WHERE id='20000000-0000-4000-8000-000000000009' AND status='todo') THEN RAISE EXCEPTION 'Unrelated task changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.tasks WHERE id='20000000-0000-4000-8000-000000000010' AND status='todo') THEN RAISE EXCEPTION 'Scoped completion activated a successor'; END IF;
END $$;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ BEGIN
 UPDATE public.tasks SET title='forged' WHERE id='20000000-0000-4000-8000-000000000001';
 IF FOUND THEN RAISE EXCEPTION 'RLS unexpectedly allowed a direct MQ-20 task write'; END IF;
END $$;
RESET ROLE;
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN UPDATE public.tasks SET title='forged' WHERE id='20000000-0000-4000-8000-000000000001'; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'MQ-20 task trigger guard allowed a direct write'; END IF;
END $$;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
UPDATE public.crm_deals SET assigned_to='00000000-0000-4000-8000-000000000004', assignee_ids=ARRAY['00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000005']::uuid[] WHERE id='10000000-0000-4000-8000-000000000001';
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.tasks WHERE id='20000000-0000-4000-8000-000000000001' AND assignee_id='00000000-0000-4000-8000-000000000004' AND assignee_ids=ARRAY['00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000005']::uuid[] AND visible_to=ARRAY['00000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000005']::uuid[]) THEN RAISE EXCEPTION 'CRM assignee change did not synchronize Contact task access'; END IF;
END $$;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ DECLARE ok boolean:=false; BEGIN
 BEGIN PERFORM public.execute_crm_contact_discussion_task('20000000-0000-4000-8000-000000000001','START'); EXCEPTION WHEN insufficient_privilege THEN ok:=true; END;
 IF NOT ok THEN RAISE EXCEPTION 'Removed assignee retained execution access'; END IF;
END $$;
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',false);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.execute_crm_contact_discussion_task('20000000-0000-4000-8000-000000000001','START'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unassigned MQ-20 user unexpectedly executed task'; END IF;
END $$;
RESET ROLE;
SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',false);
SELECT public.execute_crm_contact_discussion_task('20000000-0000-4000-8000-000000000001','COMPLETE'); RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.tasks WHERE id='20000000-0000-4000-8000-000000000001' AND status='completed') THEN RAISE EXCEPTION 'Current assignee could not complete Contact task'; END IF;
 IF has_function_privilege('anon','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE') OR has_function_privilege('service_role','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Execution RPC grant is too broad'; END IF;
 IF NOT has_function_privilege('authenticated','public.execute_crm_contact_discussion_task(uuid,text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Authenticated execution grant missing'; END IF;
 IF has_function_privilege('authenticated','hrsys_private.valid_mq20_task_context(uuid,text,text)','EXECUTE') OR has_function_privilege('authenticated','hrsys_private.is_mq20_notification_suppressed(uuid)','EXECUTE') OR has_schema_privilege('authenticated','hrsys_private','USAGE') THEN RAISE EXCEPTION 'Private MQ-20 helper access is too broad'; END IF;
END $$;
DROP TABLE public.mq20_test_expected_counts;
`;

let dockerContainer;
const run = (name, args, options = {}) => {
  if (dockerMode) return postgresDocker.run(name, args, dockerContainer);
  const r = cp.spawnSync(bin(name), args, { encoding: 'utf8', windowsHide: true, ...options });
  if (r.error) throw r.error;
  if (r.status !== 0) throw new Error(`${name} failed (${r.status}):\n${r.stdout || ''}\n${r.stderr || ''}`);
  return r.stdout || '';
};
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

const startPsqlSession = (scriptPath, port) => {
  const args = ['-X', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres', '-f', scriptPath];
  const child = dockerMode
    ? postgresDocker.spawnPsql(dockerContainer, args)
    : cp.spawn(bin('psql'), args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  const session = { child, stdout: '', stderr: '', markerWaiters: [] };
  child.stdout.on('data', chunk => {
    session.stdout += chunk.toString();
    for (const waiter of [...session.markerWaiters]) if (session.stdout.includes(waiter.marker)) {
      session.markerWaiters.splice(session.markerWaiters.indexOf(waiter), 1);
      waiter.resolve();
    }
  });
  child.stderr.on('data', chunk => { session.stderr += chunk.toString(); });
  session.done = new Promise(resolve => child.once('close', code => resolve(code)));
  session.waitFor = marker => new Promise((resolve, reject) => {
    if (session.stdout.includes(marker)) return resolve();
    if (child.exitCode !== null) return reject(new Error(`psql exited before marker ${marker}: ${session.stdout}\n${session.stderr}`));
    session.markerWaiters.push({ marker, resolve, reject });
  });
  return session;
};

(async () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hrsys-mq20-pg-'));
  const data = path.join(temp, 'data'); const log = path.join(temp, 'postgres.log');
  const reserve = net.createServer(); let port; let started = false; let proc; let logFd;
  try {
    if (dockerMode) {
      const disposable = await postgresDocker.start('hrsys-pg17-mq20-concurrency');
      dockerContainer = disposable.name;
      port = 5432;
      started = true;
      console.log(`Disposable Docker PostgreSQL ${disposable.version} (network=none; no published port).`);
    } else {
      await new Promise((resolve, reject) => reserve.listen(0, '127.0.0.1', resolve).once('error', reject));
      port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
      run('initdb', ['-D', data, '-U', 'postgres', '--auth=trust', '--no-locale', '-E', 'UTF8']);
      logFd = fs.openSync(log, 'wx');
      proc = cp.spawn(bin('postgres'), ['-D', data, '-h', '127.0.0.1', '-p', String(port), '-c', 'listen_addresses=127.0.0.1'], { windowsHide: true, stdio: ['ignore', logFd, logFd] });
      let ready = false;
      for (let i = 0; i < 80; i += 1) {
        if (proc.exitCode !== null) throw new Error(`Disposable PostgreSQL exited early; log at ${log}`);
        if (cp.spawnSync(bin('pg_isready'), ['-h','127.0.0.1','-p',String(port),'-U','postgres'], { windowsHide: true }).status === 0) { ready = true; break; }
        await wait(250);
      }
      assert.ok(ready, `Disposable PostgreSQL did not start; log at ${log}`); started = true;
    }
    const completionCall = "SELECT public.execute_crm_contact_discussion_task('20000000-0000-4000-8000-000000000001','COMPLETE');";
    const completionIndex = assertions.indexOf(completionCall);
    assert.ok(completionIndex > 0, 'Completion call anchor for multi-session race tests is missing.');
    const beforeConcurrency = assertions.slice(0, completionIndex);
    const afterConcurrency = assertions.slice(completionIndex);
    const sql = path.join(temp, 'test.sql');
    const beforeConcurrencyFile = path.join(temp, 'before-concurrency.sql');
    const afterConcurrencyFile = path.join(temp, 'after-concurrency.sql');
    fs.writeFileSync(sql, `${baseline}\n${triggers}\n${migration}`, 'utf8');
    fs.writeFileSync(beforeConcurrencyFile, beforeConcurrency, 'utf8');
    run('psql', ['-X','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p',String(port),'-U','postgres','-d','postgres','-f',sql]);
    const afterPrefix = `SELECT set_config('test.mq20.deal_id','10000000-0000-4000-8000-000000000001',false);\nSELECT set_config('test.mq20.task_id','20000000-0000-4000-8000-000000000001',false);\nSELECT set_config('test.mq20.notifications_before',(SELECT notifications::text FROM public.mq20_test_expected_counts),false);\nSELECT set_config('test.mq20.outbox_before',(SELECT outbox::text FROM public.mq20_test_expected_counts),false);\nSET ROLE authenticated;\nSELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',false);\n`;
    fs.writeFileSync(afterConcurrencyFile, `${afterPrefix}${afterConcurrency}`, 'utf8');
    run('psql', ['-X','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p',String(port),'-U','postgres','-d','postgres','-f',beforeConcurrencyFile]);

    const dealId = '10000000-0000-4000-8000-000000000001';
    const taskId = '20000000-0000-4000-8000-000000000001';
    const user1 = '00000000-0000-4000-8000-000000000004';
    const user2 = '00000000-0000-4000-8000-000000000005';
    const raceOneHolder = path.join(temp, 'race-one-holder.sql');
    const raceOneCaller = path.join(temp, 'race-one-caller.sql');
    fs.writeFileSync(raceOneHolder, `BEGIN; UPDATE public.crm_deals SET assigned_to='${user2}', assignee_ids=ARRAY['${user2}']::uuid[] WHERE id='${dealId}'; \\echo REASSIGNMENT_LOCK_HELD\nSELECT pg_sleep(1.5); COMMIT;`, 'utf8');
    fs.writeFileSync(raceOneCaller, `SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user1}',false); SELECT public.execute_crm_contact_discussion_task('${taskId}','START');`, 'utf8');
    const holderOne = startPsqlSession(raceOneHolder, port);
    await holderOne.waitFor('REASSIGNMENT_LOCK_HELD');
    const oldAssigneeCall = startPsqlSession(raceOneCaller, port);
    await wait(250);
    assert.equal(oldAssigneeCall.child.exitCode, null, 'Old assignee was not forced to wait for the concurrent deal reassignment.');
    assert.equal(await holderOne.done, 0, `Reassignment holder failed:\n${holderOne.stdout}\n${holderOne.stderr}`);
    const staleCallExit = await oldAssigneeCall.done;
    assert.notEqual(staleCallExit, 0, `Concurrent old-assignee execution unexpectedly succeeded:\n${oldAssigneeCall.stdout}`);
    assert.match(oldAssigneeCall.stderr, /Only a current CRM deal assignee may execute this task/i);

    run('psql', ['-X','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p',String(port),'-U','postgres','-d','postgres','-c',
      `UPDATE public.crm_deals SET assigned_to='${user1}', assignee_ids=ARRAY['${user1}','${user2}']::uuid[] WHERE id='${dealId}'`]);
    const raceTwoExecutor = path.join(temp, 'race-two-executor.sql');
    const raceTwoReassignment = path.join(temp, 'race-two-reassignment.sql');
    fs.writeFileSync(raceTwoExecutor, `SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user1}',false); BEGIN; SELECT public.execute_crm_contact_discussion_task('${taskId}','START'); \\echo EXECUTION_LOCK_HELD\nSELECT pg_sleep(1.5); COMMIT;`, 'utf8');
    fs.writeFileSync(raceTwoReassignment, `BEGIN; UPDATE public.crm_deals SET assigned_to='${user2}', assignee_ids=ARRAY['${user2}']::uuid[] WHERE id='${dealId}'; \\echo REASSIGNMENT_AFTER_EXECUTION\nCOMMIT;`, 'utf8');
    const executor = startPsqlSession(raceTwoExecutor, port);
    await executor.waitFor('EXECUTION_LOCK_HELD');
    const reassignmentAfterExecution = startPsqlSession(raceTwoReassignment, port);
    await wait(250);
    assert.equal(reassignmentAfterExecution.child.exitCode, null, 'Concurrent reassignment did not wait for the authorized execution transaction.');
    assert.equal(await executor.done, 0, `Authorized execution transaction failed:\n${executor.stdout}\n${executor.stderr}`);
    assert.equal(await reassignmentAfterExecution.done, 0, `Reassignment after execution failed:\n${reassignmentAfterExecution.stdout}\n${reassignmentAfterExecution.stderr}`);
    run('psql', ['-X','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p',String(port),'-U','postgres','-d','postgres','-c',
      `UPDATE public.crm_deals SET assigned_to='${user1}', assignee_ids=ARRAY['${user1}','${user2}']::uuid[] WHERE id='${dealId}'`]);

    const result = run('psql', ['-X','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p',String(port),'-U','postgres','-d','postgres','-f',afterConcurrencyFile]);
    const version = run('psql', ['-X','-A','-t','-h','127.0.0.1','-p',String(port),'-U','postgres','-d','postgres','-c','SHOW server_version']).trim();
    console.log(`Disposable PostgreSQL ${version} (${dockerMode ? 'isolated Docker; no network or published port' : 'localhost-only'}).`);
    console.log('PASS: synthetic MQ-20 action, direct-write denial, CRM assignment sync/revocation, notification/outbox suppression, grant assertions, and two true concurrent session orders (reassignment-first revokes stale execution; execution-first holds locks before reassignment).');
    if (result.includes('ERROR')) throw new Error('Unexpected PostgreSQL error text in successful runtime output.');
  } finally {
    if (started) {
      if (dockerMode) {
        postgresDocker.stop(dockerContainer);
        dockerContainer = undefined;
        started = false;
      } else {
        const stop = cp.spawnSync(bin('pg_ctl'), ['-D',data,'-m','fast','-w','stop'], { windowsHide: true, encoding: 'utf8' });
        if (stop.status !== 0) console.error('Disposable test cluster did not stop; retained for review:', temp);
        else started = false;
      }
    }
    if (!started) { try { fs.rmSync(temp, { recursive: true, force: true }); } catch (e) { console.error(`Could not remove only the test-created temp directory: ${e.message}`); } }
    if (logFd !== undefined) fs.closeSync(logFd);
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
