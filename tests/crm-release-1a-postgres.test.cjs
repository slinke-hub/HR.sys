// Actual PostgreSQL, synthetic fixtures only. Creates its own fresh cluster;
// never reads connection settings or connects to an existing database.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync, spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const bin = process.env.CRM_TEST_POSTGRES_BIN || 'C:/Program Files/PostgreSQL/18/bin';
const scratch = path.join(root, 'scratch', `crm-release-1a-pg-${Date.now()}`);
fs.mkdirSync(scratch, { recursive: true });
const data = path.join(scratch, 'data');
const port = 56541;
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.toUpperCase().startsWith('PG')));
Object.assign(env, { PGHOST: '127.0.0.1', PGPORT: String(port), PGUSER: 'postgres', PGDATABASE: 'postgres' });
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
const sql = text => run('psql', ['-X', '-v', 'ON_ERROR_STOP=1', '-qAt'], text);
function sourceFunction(file, name) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const start = source.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert(start >= 0, name);
  const end = source.indexOf('$$;', source.indexOf('AS $$', start)) + 3;
  assert(end > start, name);
  return source.slice(start, end);
}
function asyncSql(text) {
  return new Promise((resolve, reject) => {
    const child = spawn(path.join(bin, 'psql.exe'), ['-X', '-v', 'ON_ERROR_STOP=1', '-qAt'], { env, windowsHide: true });
    let out = '', err = '';
    child.stdout.on('data', v => out += v); child.stderr.on('data', v => err += v);
    child.on('error', reject); child.on('close', code => code === 0 ? resolve(out) : reject(new Error(err)));
    child.stdin.end(text);
  });
}
(async () => {
  run('initdb', ['-D', data, '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8']);
  let started = false;
  try {
    run('pg_ctl', ['-D', data, '-l', path.join(scratch, 'server.log'), '-o', `-h 127.0.0.1 -p ${port}`, '-w', 'start']);
    started = true;
    sql(fs.readFileSync(path.join(__dirname, 'fixtures/crm-release-1a-baseline.sql'), 'utf8'));
    const crm = 'supabase/migrations/20260908100000_sales_marketing_crm_and_mq07_design_access.sql';
    const permissions = 'supabase/migrations/20260908130000_executive_companywide_task_assignment.sql';
    const services = 'supabase/migrations/20260917090000_shared_business_logic_services.sql';
    const taskServices = 'supabase/migrations/20260917110000_task_backend_services.sql';
    sql([
      sourceFunction(crm, 'can_access_crm'),
      sourceFunction('supabase/migrations/20260915160000_business_financial_visibility.sql','can_view_business_financials'),
      sourceFunction('supabase/migrations/20260930104000_productivity_phase_a.sql','can_execute_task'),
      sourceFunction('supabase/migrations/20260912104500_email_attachments_and_photos.sql','queue_task_notification'),
      sourceFunction('tasks_teamwork_workflow_migration.sql','notify_task_change'),
      ...['can_assign_tasks_company_wide','can_add_task_to_list','can_view_task_list'].map(n => sourceFunction(permissions,n)),
      ...['can_access_task','can_manage_task','record_task_activity'].map(n => sourceFunction(taskServices,n)),
      sourceFunction('supabase/migrations/20260930104000_productivity_phase_a.sql','get_my_day'),
      ...['create_task_secure','change_task_status','mark_crm_deal_lost'].map(n => sourceFunction(services,n)),
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
    sql(migrationSql);
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
    sql(`CREATE TRIGGER enforce_private_task_list_ownership_trigger BEFORE INSERT OR UPDATE OF task_list_id,created_by,assignee_id,supervisor_id,visibility,visible_to,watchers ON tasks FOR EACH ROW EXECUTE FUNCTION enforce_private_task_list_ownership();
      CREATE TRIGGER crm_design_task_completion_trigger BEFORE UPDATE OF status ON tasks FOR EACH ROW EXECUTE FUNCTION enforce_crm_design_task_completion();
      CREATE TRIGGER enforce_task_completion_approval_trigger BEFORE INSERT OR UPDATE OF status ON tasks FOR EACH ROW EXECUTE FUNCTION enforce_task_completion_approval();
      GRANT EXECUTE ON FUNCTION create_task_secure(jsonb), change_task_status(uuid,text) TO authenticated;`);
    const results = sql(fs.readFileSync(path.join(__dirname, 'fixtures/crm-release-1a-assertions.sql'), 'utf8'));
    console.log('PASS: shipped trigger and privilege corrections are idempotent when reapplied');
    const actor = n => `SET ROLE authenticated; SET request.jwt.claim.sub='00000000-0000-0000-0000-${String(n).padStart(12,'0')}';`;
    const concurrent = n => `${actor(n)} SELECT change_crm_deal_stage('40000000-0000-0000-0000-000000000005','QUALIFICATION')->>'task_id';`;
    const outputs = await Promise.all([asyncSql(concurrent(1)), asyncSql(concurrent(2))]);
    assert.equal(outputs[0].trim(), outputs[1].trim(), 'concurrent calls return the same original task');
    assert.equal(sql("SELECT count(*) FROM tasks WHERE crm_deal_id='40000000-0000-0000-0000-000000000005'").trim(), '1');
    fs.writeFileSync(path.join(scratch, 'results.txt'), results + '\nPASS: concurrent Contact calls create one task\n');
    console.log(results.trim());
    console.log('PASS: concurrent Contact calls create one task');
    console.log(`Actual PostgreSQL validation passed. Synthetic fixture and selected real predicates/triggers; full Supabase replay not performed. Evidence: ${scratch}`);
  } finally {
    if (started) run('pg_ctl', ['-D', data, '-m', 'fast', '-w', 'stop']);
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
