/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const app = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const createTaskSource = app.slice(
    app.indexOf('window.handleCreateTask = async function'),
    app.indexOf('function isDailyRepeatingTask')
);

assert.match(createTaskSource, /let status = 'todo';/);
assert.doesNotMatch(createTaskSource, /status = 'Pending Approval'/);
assert.doesNotMatch(createTaskSource, /status = 'review'/);
assert.match(createTaskSource, /db\.createTask\([\s\S]*?, status, effectiveSupervisor/);
assert.match(app, /const todo = tasks\.filter\(t => t\.status === 'todo'\)/);
assert.match(app, /status: 'todo'/);

console.log('task-created-status-default: PASS');
