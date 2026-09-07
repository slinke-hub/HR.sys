const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260907150000_executive_admin_access.sql'), 'utf8');

assert.match(app, /const isExecutiveAdminProfile/);
assert.match(app, /'GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'/);
assert.equal((app.match(/currentUserRole = isExecutiveAdminProfile\(profile\) \? 'ADMIN' : profile\.role/g) || []).length, 2);
assert.match(app, /if \(viewId === 'users'\) return canCurrentUserManageUsers\(\)/);
assert.match(app, /if \(usersNav\) usersNav\.style\.display = canManageUsers \? 'flex' : 'none'/);
assert.match(app, /canManageUsers \? `<button class="btn-secondary" data-admin-tab="users"/);
assert.match(app, /if \(!canCurrentUserManageUsers\(\)\) return '<div style="padding: 2rem;">Unauthorized<\/div>'/);
assert.match(app, /const canViewAllAttendance = isAdminRole\(normalizedRole\) \|\| isExecutiveAdminProfile\(viewerProfile\)/);
assert.match(app, /db\.fetchTimePunches\(canViewAllAttendance \? null : currentUser\?\.id\)/);
assert.match(app, /id="attendanceFilterDate"[\s\S]*value=""[\s\S]*onchange="applyAttendanceFilters\(\)"/);
assert.match(migration, /CREATE TRIGGER profiles_executive_admin_role/);
assert.match(migration, /NEW\.role := 'ADMIN'/);
assert.match(migration, /UPDATE public\.profiles[\s\S]*SET role = 'ADMIN'[\s\S]*is_executive_admin_title\(job_title\)/);
assert.match(migration, /CREATE POLICY executive_admin_full_attendance_select/);
assert.match(migration, /USING \(public\.can_view_all_attendance\(auth\.uid\(\)\)\)/);

console.log('GM and CEO accounts receive admin access without User Management UI access.');
