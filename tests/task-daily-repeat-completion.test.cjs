/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const appSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');

assert.match(appSource, /function isDailyRepeatingTask\(task\)/);
assert.match(appSource, /String\(task\?\.repeat_type \|\| ''\)\.trim\(\)\.toUpperCase\(\) === 'DAILY'/);

// Daily repeating tasks skip initial approval and start in To do.
assert.match(appSource, /String\(repeatType\)\.toUpperCase\(\) === 'DAILY' && status === 'Pending Approval'[\s\S]*status = 'todo'/);

// Direct stage changes and drag-and-drop must both bypass completion approval.
assert.match(appSource, /status === 'completed' && task && !isDepartmentManager && !isDailyRepeatingTask\(task\)/);
assert.match(appSource, /const bypassesCompletionApproval = isDailyRepeatingTask\(task\)/);
assert.match(appSource, /currentStatus === 'Pending Approval'[\s\S]*!bypassesCompletionApproval/);
assert.match(appSource, /status === 'completed' && task && !isDepartmentManager && !bypassesCompletionApproval/);

console.log('Daily repeating task completion tests passed.');
