const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260908110000_marketing_manager_employee_task_access.sql'), 'utf8');

assert.match(app, /const isMarketingManagedTaskList = list => \/design\|marketing\|sales/);
assert.match(app, /const isMarketingManagerProfile/);
assert.match(app, /window\.isMarketingDepartmentManager && isMarketingManagedTaskList\(list\)/);
assert.match(app, /const canEditTaskRecord = task =>/);
assert.match(app, /canMarketingManagerEditTask\(task\)/);
assert.match(app, /if \(!canEditTaskRecord\(task\) \|\| isMq20Profile\(\)\)/);

assert.match(app, /const isMq20Profile = .*employee_id.*MQ-20/);
assert.match(app, /if \(isMq20Profile\(viewerProfile\)\) return canViewTaskViaEmployeeGrant\(task\)/);
assert.match(app, /let canCreateTask = !!currentUser && !isMq20Profile\(\)/);
assert.match(app, /This account has view-only task access/);
assert.match(app, /task-access-locked/);
assert.match(app, /const canComment = canInteractWithTask\(task\)/);

assert.match(app, /id="taskEmployeeAccessModal"/);
assert.match(app, /window\.handleSaveTaskEmployeeAccess/);
assert.match(app, /window\.removeTaskEmployeeAccess/);
assert.match(db, /async fetchTaskEmployeeAccessGrants\(\)/);
assert.match(db, /async setTaskEmployeeAccessGrant\(viewerId, subjectId, enabled = true\)/);
assert.match(css, /\.task-employee-access-content/);

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.task_employee_access_grants/);
assert.match(migration, /CREATE POLICY marketing_manager_tasks_update/);
assert.match(migration, /CREATE POLICY marketing_and_granted_tasks_select/);
assert.match(migration, /CREATE POLICY mq20_only_ines_tasks_select ON public\.tasks AS RESTRICTIVE/);
assert.match(migration, /CREATE POLICY mq20_no_tasks_insert ON public\.tasks AS RESTRICTIVE/);
assert.match(migration, /CREATE POLICY mq20_no_tasks_update ON public\.tasks AS RESTRICTIVE/);
assert.match(migration, /CREATE POLICY mq20_no_tasks_delete ON public\.tasks AS RESTRICTIVE/);
assert.match(migration, /mq20_no_task_comments_insert/);
assert.match(migration, /mq20_no_task_attachments_insert/);
assert.match(migration, /profile\.employee_id.*MQ-20/);
assert.match(migration, /\(ines\|enas\).*\(modani\|madani\)/);
assert.match(migration, /MQ-20 has fixed view-only access to Ines Modani tasks/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.set_task_employee_access_grant/);

console.log('Marketing Manager task control and MQ-20 read-only access tests passed.');
