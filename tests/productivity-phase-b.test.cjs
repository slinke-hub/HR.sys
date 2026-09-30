const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const sql = read('supabase/staging/productivity_phase_b.sql');
const app = read('js/app.js');
const db = read('js/db.js');
const services = read('js/shared-services.js');
const domain = read('src/shared/domain-services.ts');
const contract = read('src/shared/productivity-contract.ts');
const deploy = read('supabase/staging/apply-productivity-phase-b.ps1');
const verify = read('supabase/staging/productivity-phase-b-readiness-test.ps1');

for (const fn of [
  'create_task_dependency', 'remove_task_dependency', 'list_task_dependencies_secure',
  'list_task_dependency_history_secure', 'list_task_dependency_blockers_secure',
  'activate_task_successors', 'complete_and_hand_off_task'
]) assert.match(sql, new RegExp(`FUNCTION public\\.${fn}\\b`), `missing ${fn}`);
assert.match(sql, /task_dependency_would_cycle/);
assert.match(sql, /Task dependencies must stay within the same project context/);
assert.match(sql, /This dependency would create a circular workflow/);
assert.match(sql, /Task is waiting for a previous task to complete/);
assert.match(sql, /CREATE OR REPLACE FUNCTION public\.start_task[\s\S]*task_dependency_blocked\(p_task_id\)/);
assert.match(sql, /CREATE OR REPLACE FUNCTION public\.resume_task[\s\S]*task_dependency_blocked\(p_task_id\)/);
assert.match(sql, /queue_task_notification\([\s\S]*'task_ready'/);
assert.match(sql, /TASK_DEPENDENCY_READY/);
assert.match(sql, /TASK_HANDOFF/);
assert.match(sql, /REVOKE ALL ON public\.task_dependencies/);
assert.match(sql, /GRANT EXECUTE ON FUNCTION[\s\S]*complete_and_hand_off_task/);
assert.match(db, /rpc\('list_task_dependencies_secure'/);
assert.match(db, /rpc\('create_task_dependency'/);
assert.match(db, /rpc\('complete_and_hand_off_task'/);
assert.match(services, /completeAndHandOff/);
assert.match(domain, /completeAndHandOffTask/);
assert.match(contract, /TaskDependency/);
assert.match(contract, /dependency_blocked/);
assert.match(app, /Waiting for previous task/);
assert.match(app, /handleCompleteAndHandOffTask/);
assert.match(app, /fetchTaskDependencyBlockers/);
assert.match(app, /canManageTaskDependencies/);
assert.match(app, /openTaskDependencyModal/);
assert.match(app, /removeTaskDependencyFromDetail/);
assert.match(app, /db\.createTaskDependency\(selectedId, task\.id\)/);
assert.match(app, /db\.removeTaskDependency\(dependencyId\)/);
assert.match(app, /managerRole = \['ADMIN', 'MANAGER', 'SUPERVISOR', 'CEO', 'GM', 'GENERAL MANAGER'\]/);
assert.match(app, /Depends on/);
assert.match(app, /Unlocks/);
assert.match(app, /Dependency blocked/);
assert.match(app, /إنهاء وتسليم/);
assert.match(app, /title="\$\{escapeHTML\(title\)\}"/);
assert.match(app, /my-day-team-meta/);
assert.match(deploy, /jcfyyxsuspukcmybyhjj/);
assert.match(deploy, /bbbetcdioiaozdjkvwxu/);
assert.match(verify, /TEST-MANAGER/);
assert.match(verify, /TEST-EMPLOYEE/);
assert.match(verify, /TEST-OUTSIDER/);
assert.match(verify, /UseBasicParsing/);
assert.match(verify, /phase_b_diagnostic=/);
assert.match(verify, /multi_predecessor_still_blocked/);
assert.equal(deploy.includes('supabase/migrations/20'), false);
assert.equal(verify.includes('test.manager@hrsys-staging.invalid'), false);
assert.equal(verify.includes('test.employee@hrsys-staging.invalid'), false);
assert.equal(verify.includes('test.outsider@hrsys-staging.invalid'), false);
console.log('PRODUCTIVITY PHASE B STATIC TESTS: PASS');
