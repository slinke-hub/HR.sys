const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const layout = fs.readFileSync(path.join(root, 'css', 'ui-02-structural-layout.css'), 'utf8');

assert.match(app, /renderEmployeesRadarGroups\(dashboardAttendance \|\| \[\]\)/, 'Dashboard must render grouped attendance radar data');
assert.match(app, /group\('ClockedIn', currentLang === 'ar' \? 'حاضرون الآن' : 'Clocked In'/, 'Dashboard must expose a clocked-in employee group');
assert.match(app, /group\('ClockedOut', currentLang === 'ar' \? 'انصرفوا اليوم' : 'Clocked Out'/, 'Dashboard must expose a clocked-out employee group');
assert.match(app, /record\.clock_in_time && !record\.clock_out_time/, 'Clocked-in employees must have a clock-in and no clock-out');
assert.match(app, /record\.clock_in_time && record\.clock_out_time/, 'Clocked-out employees must have both punches');
assert.match(app, /if \(!hasClockIn\) return ''/, 'Employees without a clock-in must not be labeled clocked out');
assert.match(app, /new Intl\.DateTimeFormat\(currentLang === 'ar' \? 'ar-SA' : undefined/, 'Radar times must preserve Arabic/English locale formatting');
assert.match(layout, /html\[data-theme="dark"\] body:has\(\.ui02-dashboard-shell\)/, 'Cyber Obsidian theme must be scoped to the Dashboard dark state');
assert.match(layout, /#viewContainer \.employees-radar-groups[\s\S]*grid-template-columns: repeat\(2, minmax\(0, 1fr\)\)/, 'Radar groups must sit side by side on wide screens');
assert.match(layout, /@media \(max-width: 760px\)[\s\S]*\.employees-radar-groups \{ grid-template-columns: minmax\(0, 1fr\); \}/, 'Radar groups must stack on small screens');
assert.match(layout, /@media \(max-width: 440px\)[\s\S]*employees-radar-group \.employees-radar-list li/, 'Radar rows must reflow on narrow screens');

console.log('Cyber Obsidian Dashboard and Employees Radar checks passed.');
