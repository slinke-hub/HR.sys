/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');

assert.match(css, /\.notifications-dropdown\s*\{[\s\S]*?position:\s*fixed;/);
assert.match(css, /max-width:\s*calc\(100vw - 1rem\)/);
assert.match(css, /max-height:\s*var\(--notification-dropdown-max-height/);
assert.match(app, /window\.positionNotificationsDropdown = function/);
assert.match(app, /Math\.max\(preferredLeft, viewportLeft \+ margin\)/);
assert.match(app, /viewportRight - dropdownWidth - margin/);
assert.match(app, /window\.visualViewport\?\.addEventListener\('resize', window\.positionNotificationsDropdown\)/);
assert.match(app, /if \(willOpen\) \{\s*window\.positionNotificationsDropdown\(\);/);

console.log('Notification dropdown viewport checks passed.');
