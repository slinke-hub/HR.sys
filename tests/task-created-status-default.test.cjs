/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261119153000_task_status_todo_default.sql'), 'utf8');
const createTaskSource = app.slice(
    app.indexOf('window.handleCreateTask = async function'),
    app.indexOf('function isDailyRepeatingTask')
);

assert.match(createTaskSource, /let status = 'todo';/);
assert.doesNotMatch(createTaskSource, /status = 'Pending Approval'/);
assert.doesNotMatch(createTaskSource, /status = 'review'/);
assert.match(createTaskSource, /db\.createTask\([\s\S]*?, status, effectiveSupervisor/);
assert.doesNotMatch(app, /const todo = tasks\.filter\(t => t\.status === 'todo'\)/);
assert.doesNotMatch(app, /\{ status: 'todo', badge: 'todo', label: 'To Do', tone: 'slate', tasks: todo \}/);
assert.match(app, /const inProgress = tasks\.filter\(t => t\.status === 'in_progress'\)/);
assert.match(app, /const stageDefinitions = \[\s*\{ status: 'in_progress'/);
assert.match(migration, /ALTER COLUMN status SET DEFAULT 'todo'/);
assert.match(migration, /IF NEW\.status IS NULL OR NULLIF\(BTRIM\(NEW\.status\), ''\) IS NULL/);
assert.match(migration, /NEW\.status := 'todo'/);

console.log('task-created-status-default: PASS');
