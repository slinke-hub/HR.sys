/* Disposable PostgreSQL test. Synthetic records only; binds to localhost. */
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
const queueDefinition = JSON.parse(fs.readFileSync(path.join(root, 'tests/fixtures/staging-queue-task-notification.definition.json'), 'utf8')).definition;
const rawFixtureSource = fs.readFileSync(path.join(root, 'tests/fixtures/staging-crm-compatibility-schema.sql'), 'utf8');
assert.ok(rawFixtureSource.includes('-- STAGING_QUEUE_TASK_NOTIFICATION_DEFINITION'), 'Verified Staging notification definition placeholder is missing');
const fixtureSource = rawFixtureSource.replace('-- STAGING_QUEUE_TASK_NOTIFICATION_DEFINITION', `${queueDefinition};`);
const attachmentHelpersSource = fs.readFileSync(path.join(root, 'tests/fixtures/staging-crm-attachment-helpers.sql'), 'utf8');
const mq20Source = fs.readFileSync(path.join(root, 'supabase/migrations/20261109110000_mq20_contact_discussion_execution.sql'), 'utf8');
const mq20ExecutionFunction = mq20Source.match(/CREATE OR REPLACE FUNCTION public\.execute_crm_contact_discussion_task\([\s\S]*?\$function\$;/i)?.[0];
assert.ok(mq20ExecutionFunction, 'Could not extract the approved MQ-20 execution RPC from migration 2');
const stubExecutionFunction = /CREATE OR REPLACE FUNCTION public\.execute_crm_contact_discussion_task\(uuid,text,text,text\) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,pg_temp AS \$\$ SELECT '\{\}'::jsonb \$\$;/i;
assert.match(fixtureSource, stubExecutionFunction, 'Expected compatibility fixture RPC placeholder was not found');
const fixture = fixtureSource.replace(stubExecutionFunction, mq20ExecutionFunction) + '\n' + attachmentHelpersSource;
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261110100000_crm_staging_compatibility_security.sql'), 'utf8');

const assertions = String.raw`
INSERT INTO public.profiles(id,employee_id,is_active,crm_access,role,task_email_notifications) VALUES
 ('00000000-0000-4000-8000-000000000001','MQ-20',true,false,'EMPLOYEE',false),
 ('00000000-0000-4000-8000-000000000002','MQ-20',true,false,'EMPLOYEE',false),
 ('00000000-0000-4000-8000-000000000003','EMP-3',true,true,'EMPLOYEE',false),
 ('00000000-0000-4000-8000-000000000004','MQ-20',true,false,'EMPLOYEE',false),
 ('00000000-0000-4000-8000-000000000005','APPROVER',true,false,'EMPLOYEE',false);
INSERT INTO auth.users(id,email) SELECT id, 'synthetic-' || id || '@example.invalid' FROM public.profiles;
INSERT INTO public.crm_deals(id,stage,assigned_to,assignee_ids,workflow_status,title,created_by) VALUES
 ('10000000-0000-4000-8000-000000000001','QUALIFICATION','00000000-0000-4000-8000-000000000001',ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[],'CONTACT','Synthetic Contact','00000000-0000-4000-8000-000000000003'),
 ('10000000-0000-4000-8000-000000000002','PRESENTATION','00000000-0000-4000-8000-000000000005',ARRAY['00000000-0000-4000-8000-000000000005']::uuid[],'DESIGN_PENDING_APPROVAL','Synthetic Design','00000000-0000-4000-8000-000000000003');
BEGIN;
INSERT INTO public.crm_generated_tasks(deal_id,kind,task_id) VALUES
 ('10000000-0000-4000-8000-000000000001','CONTACT_DISCUSSION','20000000-0000-4000-8000-000000000001');
INSERT INTO public.tasks(id,title,description,created_by,assignee_id,assignee_ids,visible_to,crm_deal_id,crm_workflow_kind,status,notify_via_email)
VALUES ('20000000-0000-4000-8000-000000000001','Synthetic Contact task','Synthetic only','00000000-0000-4000-8000-000000000003',
 '00000000-0000-4000-8000-000000000001',
 ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[],
 ARRAY['00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002']::uuid[],
 '10000000-0000-4000-8000-000000000001','CONTACT_DISCUSSION','in_progress',false);
INSERT INTO public.tasks(id,title,created_by,assignee_id,assignee_ids,visible_to,crm_deal_id,crm_workflow_kind,status,notify_via_email)
VALUES ('20000000-0000-4000-8000-000000000002','Unregistered forged task','00000000-0000-4000-8000-000000000003',
 '00000000-0000-4000-8000-000000000001',ARRAY['00000000-0000-4000-8000-000000000001']::uuid[],
 ARRAY['00000000-0000-4000-8000-000000000001']::uuid[],'10000000-0000-4000-8000-000000000001','CONTACT_DISCUSSION','todo',false);
INSERT INTO public.tasks(id,title,created_by,assignee_id,assignee_ids,visible_to,crm_deal_id,crm_workflow_kind,status,notify_via_email)
VALUES ('20000000-0000-4000-8000-000000000003','Synthetic Design task','00000000-0000-4000-8000-000000000003',
 '00000000-0000-4000-8000-000000000005',ARRAY['00000000-0000-4000-8000-000000000005']::uuid[],
 ARRAY['00000000-0000-4000-8000-000000000005']::uuid[],'10000000-0000-4000-8000-000000000002','QUOTE_PROPOSAL_DESIGN','in_progress',false);
COMMIT;
INSERT INTO public.crm_design_task_approval_steps(id,task_id,deal_id,approver_id,status) VALUES
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000005','PENDING');
INSERT INTO public.projects(id,assigned_people) VALUES
 ('50000000-0000-4000-8000-000000000001',ARRAY['00000000-0000-4000-8000-000000000005']::uuid[]);
UPDATE public.tasks SET project_id='50000000-0000-4000-8000-000000000001'
 WHERE id='20000000-0000-4000-8000-000000000003';
INSERT INTO public.task_attachments(id,task_id,user_id,uploaded_by,file_url,file_name)
VALUES ('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000003',
        '00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000005',
        'storage://task-attachments/synthetic/design-proof.pdf','design-proof.pdf');

-- NEGOTIATION remains a first-class stage; LOST still requires its reason.
INSERT INTO public.crm_deals(id,stage,assigned_to,assignee_ids,title) VALUES
 ('10000000-0000-4000-8000-000000000003','NEGOTIATION','00000000-0000-4000-8000-000000000001',ARRAY['00000000-0000-4000-8000-000000000001']::uuid[],'Negotiation preserved');
DO $$ DECLARE denied boolean := false; BEGIN
  BEGIN
    INSERT INTO public.crm_deals(id,stage,title) VALUES ('10000000-0000-4000-8000-000000000004','LOST','Missing reason');
  EXCEPTION WHEN check_violation THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Lost deal without reason was accepted'; END IF;
END $$;
INSERT INTO public.crm_deals(id,stage,lost_reason,title) VALUES
 ('10000000-0000-4000-8000-000000000005','LOST','Synthetic reason','Lost with reason');

-- Both primary and secondary assigned MQ-20 employees read the registered task.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ BEGIN
  IF (SELECT count(*) FROM public.tasks WHERE id='20000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'Primary assignee cannot read the generated task'; END IF;
  IF (SELECT count(*) FROM public.tasks WHERE id='20000000-0000-4000-8000-000000000002') <> 0 THEN RAISE EXCEPTION 'Forged, unregistered task became visible'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
DO $$ BEGIN
  IF (SELECT count(*) FROM public.tasks WHERE id='20000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'Secondary assignee cannot read the generated task'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',false);
DO $$ BEGIN
  IF (SELECT count(*) FROM public.tasks WHERE id='20000000-0000-4000-8000-000000000001') <> 0 THEN RAISE EXCEPTION 'Unassigned MQ-20 employee can read the generated task'; END IF;
END $$;
DO $$ DECLARE denied boolean := false; BEGIN
  IF public.can_manage_task_attachments('20000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000005') THEN
    RAISE EXCEPTION 'Unassigned user forged another employee ID to manage an attachment';
  END IF;
  IF public.can_manage_task_attachments('20000000-0000-4000-8000-000000000003',auth.uid()) THEN
    RAISE EXCEPTION 'Unassigned user managed another employee task attachment';
  END IF;
  IF public.can_read_task_attachment_file('synthetic/design-proof.pdf','00000000-0000-4000-8000-000000000005') THEN
    RAISE EXCEPTION 'Unassigned user forged another employee ID to read an attachment';
  END IF;
  IF public.can_read_task_attachment_file('synthetic/design-proof.pdf',auth.uid()) THEN
    RAISE EXCEPTION 'Unassigned user read an unrelated task attachment';
  END IF;
  BEGIN
    PERFORM public.is_mq20_profile('00000000-0000-4000-8000-000000000005');
  EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Attachment helper context retained direct arbitrary MQ-20 helper access'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000005',false);
DO $$ BEGIN
  IF NOT public.can_manage_task_attachments('20000000-0000-4000-8000-000000000003',auth.uid()) THEN
    RAISE EXCEPTION 'Assigned employee lost task attachment management access';
  END IF;
  IF NOT public.can_read_task_attachment_file('synthetic/design-proof.pdf',auth.uid()) THEN
    RAISE EXCEPTION 'Assigned employee lost read access to an existing task attachment';
  END IF;
  IF public.can_read_task_attachment_file('synthetic/design-proof.pdf','00000000-0000-4000-8000-000000000004') THEN
    RAISE EXCEPTION 'Attachment reader accepted a mismatched employee ID';
  END IF;
END $$;
RESET ROLE;
UPDATE public.profiles SET is_active=false WHERE id='00000000-0000-4000-8000-000000000002';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
DO $$ BEGIN
  IF public.crm_is_own_generated_contact_task('20000000-0000-4000-8000-000000000001',auth.uid()) THEN RAISE EXCEPTION 'Inactive employee retained Contact-task access'; END IF;
END $$;
RESET ROLE;
UPDATE public.profiles SET is_active=true WHERE id='00000000-0000-4000-8000-000000000002';

-- Current deal assignment is authoritative before task-array synchronization.
UPDATE public.crm_deals SET assigned_to='00000000-0000-4000-8000-000000000001', assignee_ids=ARRAY['00000000-0000-4000-8000-000000000001']::uuid[] WHERE id='10000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
DO $$ BEGIN
  IF public.crm_is_own_generated_contact_task('20000000-0000-4000-8000-000000000001',auth.uid()) THEN RAISE EXCEPTION 'Removed assignee retained CRM-derived access'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
RESET ROLE;
UPDATE public.tasks SET assignee_id='00000000-0000-4000-8000-000000000001', assignee_ids=ARRAY['00000000-0000-4000-8000-000000000001']::uuid[], visible_to=ARRAY['00000000-0000-4000-8000-000000000001']::uuid[] WHERE id='20000000-0000-4000-8000-000000000001';

-- Archived and Lost deal conditions suppress the scoped reader helper.
UPDATE public.tasks SET archived_at=now() WHERE id='20000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ BEGIN
  IF public.crm_is_own_generated_contact_task('20000000-0000-4000-8000-000000000001',auth.uid()) THEN RAISE EXCEPTION 'Archived Contact task remained CRM-visible'; END IF;
END $$;
RESET ROLE;
UPDATE public.tasks SET archived_at=NULL WHERE id='20000000-0000-4000-8000-000000000001';
UPDATE public.crm_deals SET stage='LOST', lost_reason='Synthetic loss' WHERE id='10000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $$ BEGIN
  IF public.crm_is_own_generated_contact_task('20000000-0000-4000-8000-000000000001',auth.uid()) THEN RAISE EXCEPTION 'Lost deal Contact task remained CRM-visible'; END IF;
END $$;
RESET ROLE;

-- Direct notification RPC calls are denied, but the authenticated Design
-- approval's SECURITY DEFINER trigger chain still writes a notification.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',false);
DO $$ DECLARE denied boolean := false; BEGIN
  BEGIN PERFORM public.queue_task_notification('20000000-0000-4000-8000-000000000003',auth.uid(),'test','test');
  EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Authenticated user directly invoked privileged notification RPC'; END IF;
END $$;
DO $$ DECLARE denied boolean := false; BEGIN
  BEGIN PERFORM public.decide_crm_design_task_approval('30000000-0000-4000-8000-000000000001','APPROVED',NULL);
  EXCEPTION WHEN raise_exception THEN denied := position('assigned approver' IN SQLERRM) > 0; END;
  IF NOT denied THEN RAISE EXCEPTION 'Unauthorized authenticated user approved a Design task'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000005',false);
SELECT public.decide_crm_design_task_approval('30000000-0000-4000-8000-000000000001','APPROVED',NULL);
RESET ROLE;
DO $$ BEGIN
  IF (SELECT stage FROM public.crm_deals WHERE id='10000000-0000-4000-8000-000000000002') <> 'NEGOTIATION' THEN RAISE EXCEPTION 'Approved Design workflow did not preserve Negotiation'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE task_id='20000000-0000-4000-8000-000000000003' AND event_type='task_status_changed') THEN RAISE EXCEPTION 'Trusted internal notification generation failed after client EXECUTE revoke'; END IF;
  IF has_function_privilege('anon','public.queue_task_notification(uuid,uuid,text,text)','EXECUTE') OR has_function_privilege('authenticated','public.queue_task_notification(uuid,uuid,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Privileged notification RPC remains client-executable'; END IF;
  IF NOT has_function_privilege('service_role','public.queue_task_notification(uuid,uuid,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Trusted service role lost notification RPC EXECUTE'; END IF;
  IF NOT has_function_privilege('authenticated','public.decide_crm_design_task_approval(uuid,text,text)','EXECUTE') OR has_function_privilege('anon','public.decide_crm_design_task_approval(uuid,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Design approval grants are incorrect'; END IF;
END $$;
`;

let dockerContainer;
const run = (name, args, options = {}) => {
  if (dockerMode) return postgresDocker.run(name, args, dockerContainer);
  const result = cp.spawnSync(bin(name), args, { encoding: 'utf8', windowsHide: true, ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${name} failed (${result.status}):\n${result.stdout || ''}\n${result.stderr || ''}`);
  return result.stdout || '';
};
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const acceptsConnections = port => new Promise(resolve => {
  const socket = net.createConnection({ host: '127.0.0.1', port });
  socket.setTimeout(300);
  socket.once('connect', () => { socket.destroy(); resolve(true); });
  socket.once('error', () => resolve(false));
  socket.once('timeout', () => { socket.destroy(); resolve(false); });
});

(async () => {
  const tempRoot = process.env.HRSYS_TEST_TMPDIR || os.tmpdir();
  const temp = fs.mkdtempSync(path.join(tempRoot, 'hrsys-crm-compat-pg-'));
  const data = path.join(temp, 'data');
  const reserve = net.createServer();
  let port;
  let started = false;
  let proc;
  let logFd;
  try {
    if (dockerMode) {
      const disposable = await postgresDocker.start('hrsys-pg17-compatibility');
      dockerContainer = disposable.name;
      port = 5432;
      started = true;
      console.log(`Disposable Docker PostgreSQL ${disposable.version} (network=none; no published port).`);
    } else {
      await new Promise((resolve, reject) => reserve.listen(0, '127.0.0.1', resolve).once('error', reject));
      port = reserve.address().port;
      await new Promise(resolve => reserve.close(resolve));
      run('initdb', ['-D', data, '-U', 'postgres', '--auth=trust', '--no-locale', '-E', 'UTF8']);
      logFd = fs.openSync(path.join(temp, 'postgres.log'), 'wx');
      proc = cp.spawn(bin('postgres'), ['-D', data, '-h', '127.0.0.1', '-p', String(port), '-c', 'listen_addresses=127.0.0.1'], { windowsHide: true, stdio: ['ignore', logFd, logFd] });
      started = true;
      console.log('Disposable PostgreSQL initialized; waiting for its localhost listener.');
      let ready = false;
      for (let i = 0; i < 80; i += 1) {
        if (proc.exitCode !== null) throw new Error(`Disposable PostgreSQL exited early; retained logs: ${temp}`);
        if (await acceptsConnections(port)) { ready = true; break; }
        await wait(250);
      }
      assert.ok(ready, `Disposable PostgreSQL did not start; retained logs: ${temp}`);
    }
    const sqlFile = path.join(temp, 'test.sql');
    const fixtureFile = path.join(temp, 'fixture.sql');
    const migrationFile = path.join(temp, 'compatibility-migration.sql');
    const assertionsFile = path.join(temp, 'assertions.sql');
    fs.writeFileSync(fixtureFile, fixture, 'utf8');
    fs.writeFileSync(migrationFile, migration, 'utf8');
    fs.writeFileSync(assertionsFile, assertions, 'utf8');
    const psqlArgs = ['-X', '-v', 'ON_ERROR_STOP=1', '-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres'];
    console.log('Importing the synthetic Staging catalog fixture, then capturing the 13 MQ-20 policy definitions.');
    run('psql', [...psqlArgs, '-f', fixtureFile]);
    const fingerprintQuery = `SELECT jsonb_object_agg(signature, fingerprint ORDER BY signature)::text FROM (SELECT signature, md5(pg_get_functiondef(to_regprocedure(signature))) AS fingerprint FROM unnest(ARRAY['public.enforce_deal_workflow_transition()','public.can_view_own_crm_contact_task(uuid,uuid)','public.crm_is_own_generated_contact_task(uuid,uuid)','public.decide_crm_design_task_approval(uuid,text,text)','public.queue_task_notification(uuid,uuid,text,text)']) signature) functions`;
    console.log(`Preflight Staging function fingerprints: ${run('psql', [...psqlArgs, '-A', '-t', '-c', fingerprintQuery]).trim()}`);
    const policyQuery = `SELECT COALESCE(jsonb_agg(jsonb_build_object('name',policyname,'table',tablename,'cmd',cmd,'roles',roles,'permissive',permissive,'qual',qual,'with_check',with_check) ORDER BY policyname),'[]'::jsonb)::text FROM pg_policies WHERE schemaname='public' AND policyname LIKE 'mq20_%'`;
    const beforePolicies = JSON.parse(run('psql', [...psqlArgs, '-A', '-t', '-c', policyQuery]).trim());
    assert.equal(beforePolicies.length, 13, 'The pre-migration fixture must contain all 13 exported restrictive MQ-20 policies.');
    console.log('Applying compatibility migration in the disposable database.');
    run('psql', [...psqlArgs, '-f', migrationFile]);
    const afterPolicies = JSON.parse(run('psql', [...psqlArgs, '-A', '-t', '-c', policyQuery]).trim());
    assert.equal(afterPolicies.length, 13, 'Migration altered the MQ-20 policy inventory.');
    const helperCall = /(?:public\.)?is_mq20_profile\s*\(\s*auth\.uid\s*\(\s*\)\s*\)/gi;
    const expectedPolicies = beforePolicies.map(policy => ({ ...policy, qual: policy.qual?.replace(helperCall, 'is_mq20_current_user()') ?? null, with_check: policy.with_check?.replace(helperCall, 'is_mq20_current_user()') ?? null }));
    assert.deepEqual(afterPolicies, expectedPolicies, 'The migration changed MQ-20 policy metadata or clauses beyond the caller-scoped helper substitution.');
    assert.ok(afterPolicies.every(policy => !/is_mq20_profile\s*\(/i.test(`${policy.qual || ''} ${policy.with_check || ''}`)), 'An MQ-20 policy still calls the UUID-taking helper.');
    fs.writeFileSync(sqlFile, assertions, 'utf8');
    run('psql', [...psqlArgs, '-f', assertionsFile]);
    const mq20ProbeChecks = `SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false); DO $probe$ DECLARE blocked boolean := false; BEGIN BEGIN PERFORM public.is_mq20_profile('00000000-0000-4000-8000-000000000002'); EXCEPTION WHEN insufficient_privilege THEN blocked := true; END; IF NOT blocked THEN RAISE EXCEPTION 'Authenticated user probed an arbitrary employee UUID'; END IF; IF public.is_mq20_current_user() IS DISTINCT FROM true THEN RAISE EXCEPTION 'MQ-20 current-user policy helper failed'; END IF; END $probe$; SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false); DO $self$ BEGIN IF public.is_mq20_current_user() IS DISTINCT FROM false THEN RAISE EXCEPTION 'Non-MQ-20 self-check returned the wrong value'; END IF; END $self$; RESET ROLE; SET ROLE anon; DO $anon$ DECLARE blocked boolean := false; BEGIN BEGIN PERFORM public.is_mq20_profile('00000000-0000-4000-8000-000000000001'); EXCEPTION WHEN insufficient_privilege THEN blocked := true; END; IF NOT blocked THEN RAISE EXCEPTION 'Anonymous role probed MQ-20 membership'; END IF; END $anon$; RESET ROLE;`;
    run('psql', [...psqlArgs, '-c', mq20ProbeChecks]);
    console.log('PASS: anon and authenticated cannot invoke the arbitrary-UUID helper; authenticated current-user authorization remains available.');
    const version = run('psql', ['-X', '-A', '-t', '-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres', '-c', 'SHOW server_version']).trim();
    const mq20ProfileSourceMd5 = run('psql', ['-X', '-A', '-t', '-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres', '-c', "SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_mq20_profile(uuid)'::regprocedure"]).trim();
    console.log(`Disposable PostgreSQL ${version} (${dockerMode ? 'isolated Docker; synthetic data' : 'localhost-only; synthetic data'}).`);
    console.log(`Staging MQ-20 profile helper body MD5 (prosrc): ${mq20ProfileSourceMd5}.`);
    console.log('PASS: Negotiation and Lost-reason behavior; primary/secondary assignment visibility, unassigned/inactive denial, and reassignment revocation; archived/Lost/forged identity denial; Design approval authorization; direct notification RPC denial; trusted definer notification generation.');
  } finally {
    if (started) {
      if (dockerMode) {
        postgresDocker.stop(dockerContainer);
        dockerContainer = undefined;
        started = false;
      } else {
        const stop = cp.spawnSync(bin('pg_ctl'), ['-D', data, '-m', 'fast', '-w', 'stop'], { windowsHide: true, encoding: 'utf8' });
        if (stop.status !== 0) console.error('Disposable cluster stop failed; retained for review:', temp);
        else started = false;
      }
    }
    if (!started) { try { fs.rmSync(temp, { recursive: true, force: true }); } catch (error) { console.error(`Could not remove test-created temp directory: ${error.message}`); } }
    if (logFd !== undefined) fs.closeSync(logFd);
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
