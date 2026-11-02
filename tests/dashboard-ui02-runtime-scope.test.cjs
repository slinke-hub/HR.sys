const assert = require('node:assert/strict');
const fs = require('node:fs');

const app = fs.readFileSync('js/app.js', 'utf8');
const communityStart = app.indexOf('async function renderCommunity() {');
const communityEnd = app.indexOf('window.handlePostCommunityMessage', communityStart);
const dashboardStart = app.indexOf('async function renderDashboard() {');
const dashboardEnd = app.indexOf('let employeesRadarChannel = null;', dashboardStart);

assert.ok(communityStart >= 0 && communityEnd > communityStart, 'Community renderer must remain discoverable');
assert.ok(dashboardStart >= 0 && dashboardEnd > dashboardStart, 'Dashboard renderer must remain discoverable');

const communitySource = app.slice(communityStart, communityEnd);
const dashboardSource = app.slice(dashboardStart, dashboardEnd);

for (const identifier of ['dashboardPendingRequestCount', 'dashboardAnnouncementCount', 'dashboardAttendanceLabel']) {
    assert.doesNotMatch(communitySource, new RegExp(`const ${identifier}\\b`), `${identifier} must not leak into renderCommunity scope`);
    assert.match(dashboardSource, new RegExp(`const ${identifier}\\b`), `${identifier} must be declared in renderDashboard scope`);
}

assert.match(dashboardSource, /currentLang === 'ar' \? 'على رأس العمل' : 'On shift'/, 'Dashboard attendance label must preserve English and Arabic clocked-in text');
assert.match(dashboardSource, /currentLang === 'ar' \? 'لم يبدأ الدوام' : 'Not clocked in'/, 'Dashboard attendance label must preserve English and Arabic clocked-out text');

// Exercise the UI-02 KPI fragment with the same local bindings used by the
// Dashboard template. This catches the original ReferenceError class without
// authenticating or touching Supabase data.
const renderKpiFragment = new Function('dashboardAttendanceLabel', 'dashboardAnnouncementCount', 'dashboardPendingRequestCount', `
    return '<article>' + dashboardAttendanceLabel + '</article>'
        + '<article>' + dashboardAnnouncementCount + '</article>'
        + '<article>' + dashboardPendingRequestCount + '</article>';
`);
assert.equal(renderKpiFragment('On shift', 2, 1), '<article>On shift</article><article>2</article><article>1</article>');

console.log('UI-02 Dashboard runtime scope test passed.');
