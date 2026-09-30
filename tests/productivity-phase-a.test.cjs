const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const sql = fs.readFileSync(path.join(root, 'supabase', 'staging', 'productivity_phase_a.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const services = fs.readFileSync(path.join(root, 'js', 'shared-services.js'), 'utf8');
const contract = fs.readFileSync(path.join(root, 'src', 'shared', 'productivity-contract.ts'), 'utf8');
const deploy = fs.readFileSync(path.join(root, 'supabase', 'staging', 'apply-productivity-phase-a.ps1'), 'utf8');
const verify = fs.readFileSync(path.join(root, 'supabase', 'staging', 'productivity-phase-a-readiness-test.ps1'), 'utf8');

for (const fn of ['get_my_day', 'get_my_completed_today', 'start_task', 'mark_task_waiting', 'mark_task_blocked', 'resume_task', 'complete_task_productivity', 'list_task_work_states_secure', 'list_task_work_history_secure']) {
  assert.match(sql, new RegExp(`FUNCTION public\\.${fn}\\b`), `missing ${fn}`);
  assert.match(db, new RegExp(`rpc\\(['"]${fn}['"]`), `db adapter missing ${fn}`);
}
assert.match(sql, /PERFORM public\.change_task_status\(p_task_id, 'completed'\)/);
assert.match(sql, /CREATE OR REPLACE FUNCTION public\.can_execute_task/);
assert.equal((sql.match(/public\.can_execute_task\(p_task_id, auth\.uid\(\)\)/g) || []).length, 5);
assert.match(sql, /ALTER TABLE public\.task_waiting_history ENABLE ROW LEVEL SECURITY/);
assert.match(sql, /ALTER TABLE public\.task_blocker_history ENABLE ROW LEVEL SECURITY/);
assert.match(sql, /REVOKE ALL ON FUNCTION/);
assert.match(contract, /TaskProductivityAdapter/);
assert.match(services, /productivity: Object\.freeze/);
assert.match(index, /data-view="my-day"/);
assert.match(app, /window\.handleMyDayAction/);
assert.match(deploy, /jcfyyxsuspukcmybyhjj/);
assert.match(deploy, /bbbetcdioiaozdjkvwxu/);
assert.match(verify, /TEST-MANAGER/);
assert.match(verify, /UseBasicParsing/);
assert.match(verify, /result\.status -eq 'in_progress'/);
assert.match(verify, /result\.changed/);
assert.match(verify, /resume_after_blocked/);
assert.match(verify, /after\.row\.work_state/);
assert.equal(deploy.includes('supabase/migrations/20'), false);
console.log('PRODUCTIVITY PHASE A STATIC TESTS: PASS');
