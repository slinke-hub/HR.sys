/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');

assert.match(source, /const canApproveCompletion = task\.status === 'Pending Approval' && \(isTaskAdmin\(\)/);
assert.match(source, /const canApproveCompletion = !!task && \(isTaskAdmin\(\) \|\| window\.taskDepartmentManagerByName/);
assert.match(source, /return isTaskAdmin\(\) \|\| task\?\.created_by === currentUser\?\.id/);
assert.match(source, /task_approval_requested' && \(isTaskAdmin\(\) \|\| n\.metadata\?\.department_manager_id === currentUser\.id\)/);
assert.match(source, /const canApprove = isAdmin \|\| isDepartmentHead/);
assert.match(source, /const canReject = isAdmin \|\| isDepartmentHead/);

console.log('Task admin approval tests passed.');
