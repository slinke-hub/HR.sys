/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const data = fs.readFileSync(path.join(root, 'js', 'data.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260915170000_employee_pending_request_withdrawal.sql'), 'utf8');

assert.match(migration, /source_owner = auth\.uid\(\)/);
assert.match(migration, /source_status LIKE 'PENDING%'/);
assert.match(migration, /COALESCE\(UPPER\(workflow_status\), 'PENDING'\) = 'PENDING'/);
assert.match(migration, /IF NOT actor_is_admin AND NOT owner_can_withdraw/);
assert.match(migration, /DELETE FROM public\.request_approval_workflows/);
assert.match(migration, /DELETE FROM public\.notifications/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.admin_delete_employee_request\(TEXT, UUID\) FROM PUBLIC, anon/);

assert.match(db, /async deleteEmployeeRequest\(sourceTable, sourceId\)/);
assert.match(app, /const canWithdraw = normalizedStatus === 'PENDING'/);
assert.match(app, /const ownerCanWithdraw = r\.employee_id === currentUser\?\.id/);
assert.match(app, /handleDeleteEmployeeRequest\('\$\{escapeHTML\(request\.source_table\)\}'/);
assert.match(app, /window\.handleDeleteEmployeeRequest = function \(sourceTable, requestId, requestType, withdrawal = false\)/);
assert.match(data, /req_withdraw:\s*"Withdraw request"/);
assert.match(data, /req_withdraw:\s*"سحب الطلب"/);

console.log('Employees can securely withdraw only their own requests before final approval.');
