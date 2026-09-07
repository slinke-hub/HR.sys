/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');

assert.match(source, /function bypassesTaskCompletionApproval\(task\) \{[\s\S]*isTaskAdmin\(\) \|\| task\?\.created_by === currentUser\?\.id/);
assert.match(source, /status === 'completed' && task && !isDepartmentManager && !bypassesTaskCompletionApproval\(task\)/);
assert.match(source, /const bypassesCompletionApproval = bypassesTaskCompletionApproval\(task\)/);

const taskRowsStart = source.indexOf('const taskRows = orderedFocusTasks.map(task =>');
const taskRowsEnd = source.indexOf("}).join('');", taskRowsStart);
assert.ok(taskRowsStart >= 0 && taskRowsEnd > taskRowsStart, 'Focus-view task rows were not found');
const taskRowsSource = source.slice(taskRowsStart, taskRowsEnd);
assert.match(taskRowsSource, /const canManageTask = isTaskAdmin\(\) \|\| task\.created_by === currentUser\?\.id/);

console.log('Task creator completion tests passed.');
