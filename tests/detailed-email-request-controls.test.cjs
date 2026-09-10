const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260909130000_detailed_email_request_admin_controls.sql'), 'utf8');
const emailFunction = fs.readFileSync(path.join(root, 'supabase', 'functions', 'task-notification-email', 'index.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');

assert.match(migration, /ADD COLUMN IF NOT EXISTS context_type TEXT/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS details JSONB/);
assert.match(migration, /'Task creator', public\.email_profile_name\(task_row\.created_by\)/);
assert.match(migration, /'Updated by', public\.email_profile_name\(p_actor_id\)/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.queue_request_notification/);
assert.match(migration, /TRUE, 'EMPLOYEE_REQUEST', email_details/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.admin_delete_employee_request/);
assert.match(migration, /Only administrators can delete employee requests/);
assert.match(migration, /DELETE FROM public\.request_approval_workflows/);

assert.match(emailFunction, /Task creator/);
assert.match(emailFunction, /Updated by/);
assert.match(emailFunction, /htmlDetails/);
assert.match(emailFunction, /Open employee request/);
assert.match(emailFunction, /context_type,details/);

assert.match(db, /async deleteEmployeeRequest\(sourceTable, sourceId\)/);
assert.match(db, /rpc\('admin_delete_employee_request'/);
assert.match(db, /if \(!workflow && req/);
assert.match(app, /window\.handleDeleteEmployeeRequest/);
assert.match(app, /const deleteButton = isAdmin/);
assert.match(app, /request-delete-button/);

console.log('Detailed task/request emails and admin-only employee-request deletion are wired.');
