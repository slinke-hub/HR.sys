// Actual PostgreSQL, synthetic fixtures only. Creates its own fresh cluster;
// never reads connection settings or connects to an existing database.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync, spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const bin = process.env.CRM_TEST_POSTGRES_BIN || 'C:/Program Files/PostgreSQL/18/bin';
const scratchRoot = path.resolve(root, 'scratch');
const scratch = path.resolve(process.env.CRM_TEST_SCRATCH_DIR || path.join(scratchRoot, `crm-release-1a-pg-${Date.now()}`));
assert(scratch.startsWith(`${scratchRoot}${path.sep}`), 'PostgreSQL scratch data must stay under this workspace scratch directory');
assert(/^crm-release-1a-(?:pg-|docker-test-)[a-z0-9-]+$/i.test(path.basename(scratch)), 'PostgreSQL scratch directory must be uniquely named for this test');
fs.mkdirSync(scratch, { recursive: true });
const data = path.join(scratch, 'data');
const external = process.env.CRM_TEST_POSTGRES_EXTERNAL === '1';
const externalHost = process.env.CRM_TEST_POSTGRES_HOST || '';
const externalPort = Number(process.env.CRM_TEST_POSTGRES_PORT || 0);
const externalContainerId = process.env.CRM_TEST_POSTGRES_CONTAINER_ID || '';
const externalImageId = process.env.CRM_TEST_POSTGRES_IMAGE_ID || '';
const externalDatabase = process.env.CRM_TEST_POSTGRES_DATABASE || '';
const externalPassword = process.env.CRM_TEST_POSTGRES_PASSWORD || '';
const dockerBin = process.env.CRM_TEST_DOCKER_BIN || 'docker';
const port = external ? externalPort : 56541;
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.toUpperCase().startsWith('PG')));
Object.assign(env, {
  PGHOST: external ? externalHost : '127.0.0.1',
  PGPORT: String(port),
  PGUSER: 'postgres',
  PGDATABASE: external ? externalDatabase : 'postgres'
});
if (external) env.PGPASSWORD = externalPassword;
function verifyDisposableDockerTarget() {
  assert.equal(externalHost, '127.0.0.1', 'external PostgreSQL must be loopback-only');
  assert(Number.isInteger(externalPort) && externalPort > 0 && externalPort <= 65535, 'external PostgreSQL port must be valid');
  assert.match(externalContainerId, /^[a-f0-9]{64}$/i, 'full Docker container ID is required');
  assert.match(externalImageId, /^sha256:[a-f0-9]{64}$/i, 'verified image ID is required');
  assert.equal(externalDatabase, 'crm_release_1a_test', 'only the dedicated synthetic database is permitted');
  assert(externalPassword.length >= 24, 'temporary test credential is required');
  const inspected = spawnSync(dockerBin, ['inspect', externalContainerId], { encoding: 'utf8', windowsHide: true });
  assert.equal(inspected.status, 0, 'Docker must inspect the exact disposable container');
  const [container] = JSON.parse(inspected.stdout);
  assert(container, 'Docker container identity must resolve');
  assert.equal(container.Id, externalContainerId, 'container ID must match the approved test container');
  assert.equal(container.State?.Running, true, 'test container must be running');
  assert.equal(container.Config?.Image, 'postgres:17.6', 'only the approved PostgreSQL 17.6 image may run');
  assert.equal(container.Image, externalImageId, 'container image digest must match the pulled image');
  assert.equal(container.HostConfig?.NetworkMode === 'host', false, 'host networking is forbidden');
  assert(!container.HostConfig?.Binds?.length, 'host bind mounts are forbidden');
  assert(!container.HostConfig?.Mounts?.length, 'Docker volume/bind mount configuration is forbidden');
  assert((container.Mounts || []).every(mount => mount.Type === 'tmpfs' && mount.Destination === '/var/lib/postgresql/data'),
    'only the PostgreSQL data tmpfs mount is permitted');
  assert(container.HostConfig?.Tmpfs?.['/var/lib/postgresql/data'], 'database data directory must be tmpfs-backed');
  const bindings = container.HostConfig?.PortBindings || {};
  assert.deepEqual(Object.keys(bindings), ['5432/tcp'], 'only PostgreSQL may be published');
  assert.equal(bindings['5432/tcp']?.length, 1, 'exactly one PostgreSQL host binding is required');
  assert.equal(bindings['5432/tcp'][0]?.HostIp, '127.0.0.1', 'PostgreSQL must bind only to loopback');
  const published = container.NetworkSettings?.Ports?.['5432/tcp'] || [];
  assert.equal(published.length, 1, 'Docker must report exactly one active PostgreSQL port mapping');
  assert.equal(published[0]?.HostIp, '127.0.0.1', 'active PostgreSQL mapping must bind only to loopback');
  assert.equal(Number(published[0]?.HostPort), externalPort, 'active Docker host port must match the test connection');
}
function run(exe, args, input) {
  // A background Windows postgres process can inherit captured pipe handles.
  // Redirect control-command output to a file so spawnSync can finish promptly.
  const fd = exe === 'pg_ctl' ? fs.openSync(path.join(scratch, 'control.log'), 'a') : null;
  const result = spawnSync(path.join(bin, `${exe}.exe`), args, { input, encoding: 'utf8', env, windowsHide: true, timeout: 60000,
    ...(fd !== null ? { stdio: ['ignore', fd, fd] } : {}) });
  if (fd !== null) fs.closeSync(fd);
  if (result.status !== 0) throw new Error(`${exe}: ${result.error || result.stderr || result.stdout}`);
  return result.stdout;
}
const sql = text => {
  if (external) verifyDisposableDockerTarget();
  return run('psql', ['-X', '-v', 'ON_ERROR_STOP=1', '-qAt'], text);
};
function sourceFunction(file, name) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const start = source.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert(start >= 0, name);
  const end = source.indexOf('$$;', source.indexOf('AS $$', start)) + 3;
  assert(end > start, name);
  return source.slice(start, end);
}
function sourcePolicy(file, name) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const start = source.indexOf(`CREATE POLICY ${name} `);
  assert(start >= 0, name);
  const end = source.indexOf(';', start) + 1;
  assert(end > start, name);
  return source.slice(start, end);
}
function asyncSql(text) {
  if (external) verifyDisposableDockerTarget();
  return new Promise((resolve, reject) => {
    const child = spawn(path.join(bin, 'psql.exe'), ['-X', '-v', 'ON_ERROR_STOP=1', '-qAt'], { env, windowsHide: true });
    let out = '', err = '';
    child.stdout.on('data', v => out += v); child.stderr.on('data', v => err += v);
    child.on('error', reject); child.on('close', code => code === 0 ? resolve(out) : reject(new Error(err)));
    child.stdin.end(text);
  });
}
(async () => {
  if (!external) {
    run('initdb', ['-D', data, '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
  } else {
    verifyDisposableDockerTarget();
    const identity = run('psql', ['-X', '-v', 'ON_ERROR_STOP=1', '-qAt', '-c',
      "SELECT split_part(current_setting('server_version'), ' ', 1) || '|' || current_database() || '|' || current_user"]);
    assert.equal(identity.trim(), '17.6|crm_release_1a_test|postgres', 'connected endpoint must be the verified PostgreSQL 17.6 synthetic database');
    console.log('PASS: connected endpoint is the verified disposable PostgreSQL 17.6 container');
  }
  let started = false;
  try {
    if (!external) {
      run('pg_ctl', ['-D', data, '-l', path.join(scratch, 'server.log'), '-o', `-h 127.0.0.1 -p ${port}`, '-w', 'start']);
      started = true;
    }
    console.log('RUN: synthetic baseline fixture');
    sql(fs.readFileSync(path.join(__dirname, 'fixtures/crm-release-1a-baseline.sql'), 'utf8'));
    const crm = 'supabase/migrations/20260908100000_sales_marketing_crm_and_mq07_design_access.sql';
    const permissions = 'supabase/migrations/20260908130000_executive_companywide_task_assignment.sql';
    const services = 'supabase/migrations/20260917090000_shared_business_logic_services.sql';
    const taskServices = 'supabase/migrations/20260917110000_task_backend_services.sql';
    const productivityB = 'supabase/migrations/20260930105000_productivity_phase_b.sql';
    console.log('RUN: tracked prerequisite helpers and trigger fixture');
    sql([
      sourceFunction(crm, 'can_access_crm'),
      sourceFunction('supabase/migrations/20260915160000_business_financial_visibility.sql','can_view_business_financials'),
      sourceFunction('supabase/migrations/20260930104000_productivity_phase_a.sql','can_execute_task'),
      sourceFunction('supabase/migrations/20260912104500_email_attachments_and_photos.sql','queue_task_notification'),
      sourceFunction('tasks_teamwork_workflow_migration.sql','notify_task_change'),
      ...['can_assign_tasks_company_wide','can_add_task_to_list','can_view_task_list'].map(n => sourceFunction(permissions,n)),
      ...['can_access_task','can_manage_task','list_accessible_tasks_secure','get_task_secure','record_task_activity'].map(n => sourceFunction(taskServices,n)),
      sourceFunction('supabase/migrations/20260915200000_attachment_versioning_and_project_sharing.sql','can_manage_task_attachments'),
      sourceFunction('supabase/migrations/20260930102000_deal_backend_services.sql','can_read_task_attachment_file'),
      ...['is_task_admin','can_view_task'].map(n => sourceFunction('tasks_teamwork_workflow_migration.sql',n)),
      ...['is_ines_modani_profile','is_mq20_profile','is_ines_modani_task'].map(n => sourceFunction('supabase/migrations/20260908110000_marketing_manager_employee_task_access.sql',n)),
      ...['can_view_task_via_employee_grant','can_view_task_list_via_employee_grant'].map(n => sourceFunction('supabase/migrations/20260908110000_marketing_manager_employee_task_access.sql',n)),
      sourceFunction('supabase/migrations/20260908100000_sales_marketing_crm_and_mq07_design_access.sql','is_mq07_design_list'),
      sourceFunction(permissions,'can_assign_tasks_company_wide'),
      sourceFunction('supabase/migrations/20260930104000_productivity_phase_a.sql','get_my_day'),
      ...['task_dependency_blocked','list_task_dependencies_secure','list_task_dependency_history_secure',
        'list_task_dependency_blockers_secure','list_accessible_tasks_secure','get_my_day',
        'activate_task_successors','change_task_status','complete_task_productivity',
        'complete_and_hand_off_task'].map(n => sourceFunction(productivityB,n)),
      sourceFunction(taskServices,'list_task_activity_secure'),
      ...['create_task_secure','update_task_secure','delete_task_secure','change_task_status','assign_task','mark_crm_deal_lost'].map(n => sourceFunction(services,n)),
      ...['add_task_comment','register_task_attachment'].map(n => sourceFunction(taskServices,n)),
      sourceFunction('supabase/migrations/20260901090000_task_list_permissions_and_company_watchers.sql','validate_task_department_supervisor'),
      sourceFunction('supabase/migrations/20260910150000_crm_presentation_revision_status.sql','sync_crm_design_task_status'),
      sourceFunction('supabase/migrations/20260907130000_task_creation_defaults.sql','apply_task_creation_defaults'),
      `CREATE TRIGGER validate_task_department_supervisor BEFORE INSERT OR UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION validate_task_department_supervisor();
       CREATE TRIGGER tasks_apply_creation_defaults BEFORE INSERT ON tasks FOR EACH ROW EXECUTE FUNCTION apply_task_creation_defaults();
       CREATE TRIGGER task_activity_after_insert AFTER INSERT ON tasks FOR EACH ROW EXECUTE FUNCTION record_task_activity();
       CREATE TRIGGER task_activity_after_update AFTER UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION record_task_activity();
       CREATE TRIGGER design_sync AFTER INSERT OR UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION sync_crm_design_task_status();
       CREATE TRIGGER notify_task_change_trigger AFTER INSERT OR UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION notify_task_change();`
    ].join('\n'));
    const migrationSql = fs.readFileSync(path.join(root, 'supabase/migrations/20261022100000_crm_release_1a.sql'), 'utf8');
    console.log('RUN: migration 20261022100000');
    sql(migrationSql);
    console.log('RUN: prerequisite RLS policies');
    sql([
      sourcePolicy('schema.sql','"Users can view tasks assigned to them"'),
      sourcePolicy('tasks_teamwork_workflow_migration.sql','tasks_select_authorized'),
      sourcePolicy('supabase/migrations/20260908100000_sales_marketing_crm_and_mq07_design_access.sql','mq07_design_tasks_select'),
      sourcePolicy('supabase/migrations/20260908110000_marketing_manager_employee_task_access.sql','marketing_and_granted_tasks_select'),
      sourcePolicy('supabase/migrations/20260908130000_executive_companywide_task_assignment.sql','executive_company_tasks_select'),
      sourcePolicy(taskServices,'task_secure_access_select'),
      sourcePolicy('supabase/migrations/20260908110000_marketing_manager_employee_task_access.sql','mq20_only_ines_tasks_select'),
      sourcePolicy(productivityB,'task_dependencies_secure_select'),
      sourcePolicy(taskServices,'task_activity_secure_select'),
      `GRANT SELECT ON tasks TO authenticated;
       ALTER TABLE task_dependencies ENABLE ROW LEVEL SECURITY;
       ALTER TABLE task_activity ENABLE ROW LEVEL SECURITY;
       GRANT EXECUTE ON FUNCTION can_access_task(uuid,uuid), can_view_task(uuid,uuid), is_task_admin(uuid), is_mq20_profile(uuid), is_ines_modani_task(uuid), is_mq07_design_list(uuid,uuid), can_assign_tasks_company_wide(uuid), list_task_dependencies_secure(uuid), list_task_dependency_history_secure(uuid), list_task_dependency_blockers_secure(), list_task_activity_secure(uuid), complete_and_hand_off_task(uuid,uuid) TO authenticated;`
    ].join('\n'));
    const visibilityMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20261024100000_crm_mq20_contact_task_visibility.sql'), 'utf8');
    console.log('RUN: migration 20261024100000');
    sql(visibilityMigration);
    const authorizationMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20261026100000_mq20_task_service_authorization_hardening.sql'), 'utf8');
    console.log('RUN: migration 20261026100000');
    sql(authorizationMigration);
    const appliedAuthorization = sql("SELECT count(*) FROM pg_trigger WHERE tgrelid='public.tasks'::regclass AND tgname='mq20_task_service_view_only' AND tgenabled='O'");
    assert.equal(appliedAuthorization.trim(), '1', 'MQ-20 task guard must be installed before dependency privacy migration');
    const dependencyPrivacyMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20261027100000_task_dependency_visibility_hardening.sql'), 'utf8');
    console.log('RUN: migration 20261027100000');
    sql(dependencyPrivacyMigration);
    const triggerStart = migrationSql.indexOf('DROP TRIGGER IF EXISTS crm_deals_enforce_workflow_transition');
    const triggerEndMarker = 'FOR EACH ROW EXECUTE FUNCTION public.enforce_deal_workflow_transition();';
    const triggerEnd = migrationSql.indexOf(triggerEndMarker, triggerStart) + triggerEndMarker.length;
    assert(triggerStart >= 0 && triggerEnd > triggerStart, 'shipped trigger install DDL is extractable');
    const triggerInstall = migrationSql.slice(triggerStart, triggerEnd);
    sql(triggerInstall);
    sql(triggerInstall);
    const grantStart = migrationSql.indexOf('REVOKE ALL ON FUNCTION public.can_add_task_to_list(uuid, uuid)');
    const grantEndMarker = 'GRANT EXECUTE ON FUNCTION public.can_add_task_to_list(uuid, uuid) TO authenticated;';
    const grantEnd = migrationSql.indexOf(grantEndMarker, grantStart) + grantEndMarker.length;
    assert(grantStart >= 0 && grantEnd > grantStart, 'shipped task-list grant correction is extractable');
    const grantCorrection = migrationSql.slice(grantStart, grantEnd);
    sql(grantCorrection);
    sql(grantCorrection);
    sql(`INSERT INTO tasks(id,title,assignee_id,assignee_ids,created_by,supervisor_id,department,visible_to,visibility,status)
      VALUES ('50000000-0000-0000-0000-000000000009','Synthetic authorized Ines visibility',
        '00000000-0000-0000-0000-000000000003',ARRAY['00000000-0000-0000-0000-000000000003'::uuid],
        '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005','Sales',
        ARRAY['00000000-0000-0000-0000-000000000007'::uuid],'private','todo');`);
    sql(`CREATE TRIGGER enforce_private_task_list_ownership_trigger BEFORE INSERT OR UPDATE OF task_list_id,created_by,assignee_id,supervisor_id,visibility,visible_to,watchers ON tasks FOR EACH ROW EXECUTE FUNCTION enforce_private_task_list_ownership();
      CREATE TRIGGER crm_design_task_completion_trigger BEFORE UPDATE OF status ON tasks FOR EACH ROW EXECUTE FUNCTION enforce_crm_design_task_completion();
      CREATE TRIGGER enforce_task_completion_approval_trigger BEFORE INSERT OR UPDATE OF status ON tasks FOR EACH ROW EXECUTE FUNCTION enforce_task_completion_approval();
      GRANT EXECUTE ON FUNCTION create_task_secure(jsonb), update_task_secure(uuid,jsonb), delete_task_secure(uuid),
        list_accessible_tasks_secure(), get_task_secure(uuid),
        change_task_status(uuid,text), assign_task(uuid,uuid[]), add_task_comment(uuid,text,jsonb),
        register_task_attachment(uuid,text,text,text,bigint,text,boolean) TO authenticated;`);
    console.log('RUN: CRM workflow and My Day assertions');
    const results = sql(fs.readFileSync(path.join(__dirname, 'fixtures/crm-release-1a-assertions.sql'), 'utf8'));
    sql('ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;');
    console.log('RUN: MQ-20 task-service assertions');
    const mq20Results = sql(fs.readFileSync(path.join(__dirname, 'fixtures/crm-release-1a-mq20-hardening-assertions.sql'), 'utf8'));
    console.log('RUN: dependency privacy assertions');
    const dependencyPrivacyResults = sql(fs.readFileSync(path.join(__dirname, 'fixtures/crm-release-1a-dependency-privacy-assertions.sql'), 'utf8'));
    console.log('RUN: RLS visibility assertions');
    const visibilityResults = sql(fs.readFileSync(path.join(__dirname, 'fixtures/crm-release-1a-rls-assertions.sql'), 'utf8'));
    const finalIdentity = sql("SELECT split_part(current_setting('server_version'), ' ', 1) || '|' || current_database() || '|' || current_user");
    if (external) assert.equal(finalIdentity.trim(), '17.6|crm_release_1a_test|postgres', 'test endpoint identity must remain unchanged');
    console.log('PASS: shipped trigger and privilege corrections are idempotent when reapplied');
    console.log('PASS: CRM and MQ-20 migrations were applied once in the approved order');
    const actor = n => `SET ROLE authenticated; SET request.jwt.claim.sub='00000000-0000-0000-0000-${String(n).padStart(12,'0')}';`;
    const concurrent = n => `${actor(n)} SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000005','QUALIFICATION')->>'task_id';`;
    const outputs = await Promise.all([asyncSql(concurrent(1)), asyncSql(concurrent(2))]);
    assert.equal(outputs[0].trim(), outputs[1].trim(), 'concurrent calls return the same original task');
    assert.equal(sql("SELECT count(*) FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000005'").trim(), '1');
    fs.writeFileSync(path.join(scratch, 'results.txt'), results + '\nPASS: concurrent Contact calls create one task\n');
    console.log(results.trim());
    console.log(mq20Results.trim());
    console.log(dependencyPrivacyResults.trim());
    console.log(visibilityResults.trim());
    console.log('PASS: concurrent Contact calls create one task');
    console.log(`Actual PostgreSQL validation passed. Synthetic fixture and selected real predicates/triggers; full Supabase replay not performed. Evidence: ${scratch}`);
  } finally {
    if (started) run('pg_ctl', ['-D', data, '-m', 'fast', '-w', 'stop']);
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
