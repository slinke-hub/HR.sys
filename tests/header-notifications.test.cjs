/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const htmlSource = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const appSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const cssSource = fs.readFileSync(path.join(__dirname, '..', 'css', 'components.css'), 'utf8');
const migrationSource = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260905140000_notifications_realtime.sql'), 'utf8');

assert.match(htmlSource, /id="headerNotificationsButton"/);
assert.match(htmlSource, /class="notification-badge"[^>]*hidden>0<\/span>/);
assert.match(htmlSource, /id="notificationsDropdown"/);

assert.match(appSource, /function updateNotificationBadge\(unreadCount\)/);
assert.match(appSource, /function playNotificationRing\(\)/);
assert.match(appSource, /createOscillator\(\)/);
assert.match(appSource, /table: 'notifications'/);
assert.match(appSource, /event: 'INSERT'/);
assert.match(appSource, /startNotificationsRealtime\(\)/);
assert.match(appSource, /knownNotificationIds/);
assert.match(appSource, /class="notification-title-button"/);
assert.match(appSource, /openNotificationDestination/);
assert.match(appSource, /actionView = 'requests'/);
assert.match(appSource, /openTaskNotification\(actionTaskId\)/);

assert.match(cssSource, /\.notification-badge[\s\S]*background: #dc2626/);
assert.match(cssSource, /\.notifications-dropdown\.show \{ display: block; \}/);
assert.match(cssSource, /\.notification-title-button:hover/);
assert.match(migrationSource, /ALTER PUBLICATION supabase_realtime ADD TABLE public\.notifications/);

console.log('Header notification tests passed.');
