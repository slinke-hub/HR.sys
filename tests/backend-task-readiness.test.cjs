const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const migration = read('supabase/migrations/20260917090000_shared_business_logic_services.sql')
  + '\n' + read('supabase/migrations/20260917110000_task_backend_services.sql');
const db = read('js/db.js');
const app = read('js/app.js');
const bridge = read('js/shared-services.js');
const services = read('src/shared/domain-services.ts');
const statusNotifications = read('supabase/migrations/20260927100000_task_status_notifications.sql');

for (const name of [
  'can_access_task','can_manage_task','list_accessible_tasks_secure','get_task_secure',
  'create_task_secure','update_task_secure','delete_task_secure',
  'add_task_comment','update_task_comment','delete_task_comment','list_task_comments_secure',
  'register_task_attachment','list_task_attachments_secure','remove_task_attachment',
  'list_task_activity_secure'
]) assert.match(migration, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}`));

assert.match(migration, /DROP POLICY IF EXISTS ["']task_comments_select["']/);
assert.doesNotMatch(migration, /task_comments_select[\s\S]{0,160}USING \(true\)/i);
assert.match(migration, /task_comments_secure_select/);
assert.match(migration, /task_comments_secure_insert/);
assert.match(migration, /task_activity/);
assert.match(migration, /REVOKE INSERT, UPDATE, DELETE ON public\.tasks FROM authenticated/);
assert.match(migration, /REVOKE ALL ON FUNCTION[\s\S]{0,1200}public\.add_task_comment/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION[\s\S]{0,1600}public\.register_task_attachment/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION[\s\S]{0,1600}public\.create_task_secure/);

for (const rpc of [
  "list_accessible_tasks_secure", "get_task_secure", "create_task_secure", "update_task_secure",
  "delete_task_secure", "add_task_comment", "list_task_comments_secure", "register_task_attachment", "list_task_attachments_secure",
  "remove_task_attachment", "list_task_activity_secure"
]) assert.match(db, new RegExp(`rpc\\('${rpc}'`));
for (const op of ['complete','reopen','updateComment','deleteComment','removeAttachment','activity']) assert.match(bridge, new RegExp(op));
for (const op of ['completeTask','reopenTask','updateTaskComment','deleteTaskComment','removeTaskAttachment','fetchTaskActivity']) assert.match(services, new RegExp(op));
assert.match(app, /db\.fetchTaskActivity/);
assert.match(app, /task-v2-inline-status/);
assert.match(app, /handleTaskCardStageChange\('\$\{task\.id\}', this\.value\)/);
assert.match(app, /\['canceled', taskDetailText\('Canceled', 'ملغاة'\)\]/);
assert.match(app, /status-\$\{taskStatusClass\(task\.status\)\}/);
assert.match(app, /updateTaskStatusControlClass\(select, actualStatus\)/);
assert.match(app, /task-v2-table-header/);
for (const heading of ['Task Title', 'Task Status', 'Created By', 'Actions']) assert.match(app, new RegExp(heading));
assert.match(statusNotifications, /CREATE OR REPLACE FUNCTION public\.queue_task_status_notification/);
assert.match(statusNotifications, /UNION ALL[\s\S]*NEW\.assignee_ids/);
assert.match(statusNotifications, /UNION ALL[\s\S]*NEW\.watchers/);
assert.match(statusNotifications, /event_type, task_id, actor_id/);
assert.match(statusNotifications, /always_send, context_type, details/);
assert.match(statusNotifications, /DROP TRIGGER IF EXISTS task_status_notification_trigger/);

console.log('Task backend readiness static checks passed; live RLS/IDOR tests require linked Supabase credentials.');
