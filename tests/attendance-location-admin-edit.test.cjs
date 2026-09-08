const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260908150000_attendance_location_admin_edit.sql'), 'utf8');
const linkMigration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260908160000_admin_attendance_location_links.sql'), 'utf8');

assert.match(app, /async function requestRequiredAttendanceLocation/);
assert.match(app, /const location = await requestRequiredAttendanceLocation/);
assert.doesNotMatch(app, /fallbackClockIn\("Location Unavailable"\)/);
assert.match(app, /Clock-out location verification failed/);
assert.match(app, /officeLocationClockOutButton/);
assert.match(app, /window\.openAttendanceEditModal = function/);
assert.match(app, /window\.handleAttendanceEditSubmit = async function/);
assert.match(app, /attendanceEditLocation" type="url"/);
assert.match(app, /attendanceLocationToMapsUrl/);
assert.match(app, /Enter a valid Google Maps location link/);
assert.match(app, /canEditAttendance \? `<td><button[^`]+openAttendanceEditModal/);
assert.match(db, /async updateAttendancePunch\(attendanceId, punchType, changes = \{\}\)/);
assert.match(db, /Attendance location must be a valid Google Maps link/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.is_valid_attendance_coordinates/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.enforce_attendance_coordinates/);
assert.match(migration, /CREATE TRIGGER attendance_coordinates_required/);
assert.match(migration, /CREATE POLICY admin_company_attendance_update/);
assert.match(linkMigration, /CREATE OR REPLACE FUNCTION public\.is_valid_google_maps_location/);
assert.match(linkMigration, /public\.can_manage_attendance_records\(auth\.uid\(\)\)/);
assert.match(linkMigration, /NOT public\.is_valid_attendance_coordinates\(NEW\.clock_in_location\)/);

console.log('Attendance requires location and administrators can edit employee punches.');
