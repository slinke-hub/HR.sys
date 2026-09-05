/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const appSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const cssSource = fs.readFileSync(path.join(__dirname, '..', 'css', 'components.css'), 'utf8');

assert.match(appSource, /const rowAssigneeFirstNames = rowAssigneeProfiles\.map/);
assert.match(appSource, /const rowCreator = \(window\.taskAllUsersCache \|\| \[\]\)\.find\(user => user\.id === task\.created_by\) \|\| task\.creator/);
assert.match(appSource, /class="task-focus-people"/);
assert.match(appSource, /class="task-focus-assignee"/);
assert.match(appSource, /class="task-focus-creator"/);
assert.match(appSource, /font-weight: 700/);
assert.match(appSource, /taskDetailText\('Employee', 'الموظف'\)/);
assert.match(appSource, /taskDetailText\('Created by', 'أنشأها'\)/);
assert.match(appSource, /escapeHTML\(rowAssigneeFirstName\)/);
assert.match(appSource, /escapeHTML\(rowCreatorName\)/);

assert.match(cssSource, /\.task-focus-people \{/);
assert.match(cssSource, /\.task-focus-people strong \{/);
assert.match(cssSource, /#task-v2-rows-container \.task-v2-row-content h4 \{[\s\S]*font-weight: 700 !important/);
assert.match(cssSource, /\.task-focus-assignee svg \{ color: #2563eb; \}/);
assert.match(cssSource, /\.task-focus-creator svg \{ color: #7c3aed; \}/);

console.log('Task focus people tests passed.');
