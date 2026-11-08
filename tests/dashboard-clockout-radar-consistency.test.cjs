const assert = require('node:assert/strict');
const fs = require('node:fs');

const app = fs.readFileSync('js/app.js', 'utf8');
const components = fs.readFileSync('css/components.css', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

const attendanceCard = app.match(/<article class="card ui02-command-card ui02-command-card--blue ui02-command-card--attendance">([\s\S]*?)<\/article>/);
assert.ok(attendanceCard, 'Attendance summary card includes its attendance action');
assert.ok(attendanceCard[1].indexOf('<small>') < attendanceCard[1].indexOf('id="attendanceClockButton"'), 'Clock action is placed below the attendance status and Clock-in guidance');
assert.match(attendanceCard[1], /isClockedIn[\s\S]*class="employees-radar-clockout dashboard-attendance-clockout"/, 'Clock-out remains conditional on an active clock-in and reuses the Employees Radar action class');
assert.match(attendanceCard[1], /data-lucide="log-out"/, 'Dashboard clock-out uses the same Lucide exit icon');
assert.match(attendanceCard[1], /currentLang === 'ar'[\s\S]*dashboard-clock-button-label[\s\S]*data-lucide="log-out"/, 'Arabic keeps the label before the trailing exit icon');
assert.match(attendanceCard[1], /data-lucide="log-out"[\s\S]*dashboard-clock-button-label/, 'English keeps the exit icon before its label');
assert.doesNotMatch(app.slice(app.indexOf('<div class="page-header">'), app.indexOf('<div class="ui02-dashboard-shell"')), /attendanceClockButton/, 'Attendance action is no longer detached in the page header');

assert.match(app, /const setDashboardClockOutAction = \(button, attendanceId\) =>[\s\S]*button\.classList\.add\('employees-radar-clockout', 'dashboard-attendance-clockout'\)/, 'Successful clock-in and failed clock-out restore the shared danger action treatment');
assert.match(app, /const setDashboardClockInAction = \(button\) =>[\s\S]*button\.classList\.remove\('employees-radar-clockout', 'dashboard-attendance-clockout'/, 'Optimistic clock-out restores the existing clock-in action styling');
assert.match(app, /db\.clockIn\(currentUser\.id, location\.label\)/, 'Clock-in operation remains unchanged');
assert.match(app, /db\.clockOut\(attendanceId, locationLabel, type, overtime, locationDetails\)/, 'Clock-out operation remains unchanged');

assert.match(components, /\.employees-radar-clockout \{[^}]*min-height:30px[^}]*padding:\.32rem \.55rem[^}]*border-radius:7px[^}]*font:inherit[^}]*font-size:\.68rem[^}]*font-weight:700/, 'Shared Radar compact sizing and typography remain the source of truth');
assert.match(components, /\.employees-radar-clockout:hover \{[^}]*background:[^}]*box-shadow:var\(--shadow-sm\)/, 'Shared hover treatment is retained');
assert.match(components, /\.employees-radar-clockout:focus-visible \{[^}]*outline:2px solid var\(--focus-ring\)/, 'Shared focus treatment is retained');
assert.match(components, /\.employees-radar-clockout svg \{ width:14px; height:14px; \}/, 'Shared icon dimensions are retained');
assert.match(components, /\.dashboard-attendance-clockout \{ flex:0 0 auto; white-space:nowrap; \}/, 'Main action remains compact and does not stretch');
assert.match(components, /\.employees-radar-clockout:not\(\.dashboard-attendance-clockout\) span \{ display:none; \}/, 'Mobile-only Radar icon treatment does not hide the main action label');
assert.match(components, /\.employees-radar-clockout:disabled \{ opacity:\.55; cursor:wait; transform:none; box-shadow:none; \}/, 'Shared disabled state remains legible and stable');
assert.match(html, /css\/components\.css\?v=2026110401/, 'Component styling uses the current dashboard semantic cache key');
assert.match(html, /js\/app\.js\?v=2026110803/, 'Dashboard/app markup receives a fresh cache key for the attendance control move');

console.log('Dashboard Clock Out / Employees Radar consistency checks passed.');
