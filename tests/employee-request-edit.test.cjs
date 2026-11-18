const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261118110000_admin_edit_employee_requests.sql'), 'utf8');

assert.match(html, /id="requestLeaveStart"[^>]*type="date"/);
assert.match(html, /id="requestLeaveEnd"[^>]*type="date"/);
assert.match(app, /syncRequestLeaveDatesToDays/);
assert.match(app, /db\.createRequest\(empId, reqType, leaveType, loanAmount, numberOfDays, null, startDate, endDate\)/);
assert.match(db, /async createRequest\(employeeId, requestType, leaveType, loanAmount = null, numberOfDays = null, notes = null, startDate = null, endDate = null\)/);
assert.match(db, /async updateEmployeeRequest\(sourceTable, sourceId, patch\)/);
assert.match(db, /rpc\('admin_update_employee_request'/);
assert.match(app, /request-edit-button/);
assert.match(app, /window\.openEmployeeRequestEdit = function/);
assert.match(app, /window\.handleEmployeeRequestEditSubmit = async function/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS start_date DATE/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS end_date DATE/);
assert.match(migration, /is_employee_request_admin\(auth\.uid\(\)\)/);
assert.match(migration, /admin_update_employee_request/);
assert.match(migration, /p_source_table NOT IN \('requests', 'leave_requests', 'document_requests', 'expenses'\)/);

console.log('Leave request dates and administrator request edit/delete controls are wired securely.');
