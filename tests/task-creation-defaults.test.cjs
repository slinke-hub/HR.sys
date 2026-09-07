const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260907130000_task_creation_defaults.sql'), 'utf8');

assert.match(app, /id="taskRegularUrl" type="url"/);
assert.match(html, /id="editTaskRegularUrl" type="url"/);
assert.match(app, /const isRegularTask = subType === 'Regular Task' \|\| subType === 'Regular Tasks'/);
assert.match(app, /sourceLink = document\.getElementById\('taskRegularUrl'\)/);
assert.match(app, /updates\.source_link = isRegularTask \?/);

assert.match(app, /const preferredAssigneeId = selectedAssigneeId \|\| \(prefix === 'new' \? currentUser\?\.id : ''\)/);
assert.match(app, /const effectiveAssignee = assignee \|\| currentUser\.id/);
assert.match(migration, /IF NEW\.assignee_id IS NULL THEN\s+NEW\.assignee_id := NEW\.created_by;/);

assert.match(app, /updateTaskDepartmentManager\(prefix, selectedDepartment\)/);
assert.match(app, /id="taskDepartmentManagerName"/);
assert.match(html, /id="editTaskDepartmentManagerName"/);
assert.match(app, /selectedDepartment\?\.head_id\s+\|\| selectedDepartment\?\.manager_id/);
assert.match(migration, /tasks_apply_creation_defaults/);
assert.match(migration, /department\.head_id/);

console.log('Task creation URL, assignee, and department manager defaults are wired.');
