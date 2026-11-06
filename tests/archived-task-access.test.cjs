/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const source = fs.readFileSync(path.join(root, 'src', 'crm-dashboard.jsx'), 'utf8');
const styles = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261104100000_employee_archived_task_read_access.sql'), 'utf8');

assert.match(app, /const canViewArchivedTaskRecord = task => !!task\?\.archived_at[\s\S]*?task\.created_by === currentUser\.id[\s\S]*?task\.assignee_id === currentUser\.id[\s\S]*?task\.assignee_ids\.includes\(currentUser\.id\)[\s\S]*?task\.watchers\.includes\(currentUser\.id\)/);
assert.match(app, /const canInteractWithTask = task => !!task && !task\.archived_at/);
assert.match(app, /const canOpenTaskDetails = task =>[\s\S]*canViewArchivedTaskRecord\(task\)/);
assert.match(app, /const canOpenTaskDetails = task =>[\s\S]*\(!!task\.archived_at && canEditTaskRecord\(task\)\)/);
assert.match(app, /const canCreateTask = !!currentUser && !task\.archived_at/);
assert.match(app, /const visibleArchivedTasks = isEmployee[\s\S]*task\.watchers\.includes\(currentUser\?\.id\)/);
assert.match(app, /window\.openArchivedTaskDetails = async function \(taskId\)/);
assert.match(app, /!task\.archived_at && canChangeTaskStageRecord\(task\)/);
assert.match(app, /!task\.archived_at && canManageTaskDependencies\(task\)/);

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.can_view_archived_task\(p_task_id uuid\)/i);
assert.match(migration, /SECURITY DEFINER[\s\S]*SET search_path = public, pg_temp/i);
assert.match(migration, /task\.archived_at IS NOT NULL[\s\S]*auth\.uid\(\) IS NOT NULL/i);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.can_view_archived_task\(uuid\) FROM PUBLIC, anon/i);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.can_view_archived_task\(uuid\) TO authenticated/i);
assert.match(migration, /CREATE POLICY task_secure_access_select ON public\.tasks AS RESTRICTIVE[\s\S]*public\.can_access_task\(id, auth\.uid\(\)\)[\s\S]*OR public\.can_view_archived_task\(id\)/i);
assert.match(migration, /CREATE POLICY task_archived_self_read ON public\.tasks AS PERMISSIVE[\s\S]*FOR SELECT TO authenticated[\s\S]*USING \(public\.can_view_archived_task\(id\)\)/i);
for (const reader of ['list_task_comments_secure', 'list_task_attachments_secure', 'list_task_activity_secure']) {
  assert.match(migration, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${reader}[\\s\\S]*?public\\.can_view_archived_task\\(p_task_id\\)`, 'i'));
}
assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION public\.(create_task_secure|update_task_secure|delete_task_secure|assign_task|can_access_task)\b/i);
assert.doesNotMatch(migration, /FOR (INSERT|UPDATE|DELETE|ALL)\b/i);

console.log('Archived task visibility and read-only access checks passed.');
