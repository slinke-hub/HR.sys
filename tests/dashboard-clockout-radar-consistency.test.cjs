const assert = require('node:assert/strict');
const fs = require('node:fs');

const app = fs.readFileSync('js/app.js', 'utf8');
const components = fs.readFileSync('css/components.css', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

const clockOutRender = app.match(/\? `<button id="attendanceClockButton"([\s\S]*?)`\s*:\s*`<button id="attendanceClockButton"/);
assert.ok(clockOutRender, 'Dashboard clock-out branch is present');
assert.match(clockOutRender[1], /class="employees-radar-clockout dashboard-attendance-clockout"/, 'Dashboard reuses the Employees Radar action class');
assert.match(clockOutRender[1], /data-lucide="log-out"/, 'Dashboard clock-out uses the same Lucide exit icon');
assert.match(clockOutRender[1], /currentLang === 'ar'[\s\S]*dashboard-clock-button-label[\s\S]*data-lucide="log-out"/, 'Arabic keeps the label before the trailing exit icon');
assert.match(clockOutRender[1], /data-lucide="log-out"[\s\S]*dashboard-clock-button-label/, 'English keeps the exit icon before its label');

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
assert.match(html, /css\/components\.css\?v=2026100701/, 'Component styling receives a fresh cache key');
assert.match(html, /js\/app\.js\?v=2026100701/, 'Dashboard/app markup receives the current security-fix cache key');

console.log('Dashboard Clock Out / Employees Radar consistency checks passed.');
