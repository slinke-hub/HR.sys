const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');

assert.match(app, /id="taskV2CreatorFilter"[\s\S]*All creators/);
assert.match(app, /id="taskV2AssigneeFilter"[\s\S]*All assignees/);
assert.match(app, /const matchesCreator = creator === 'all' \|\| String\(task\.created_by \|\| ''\) === creator/);
assert.match(app, /const matchesAssignee = assignee === 'all' \|\| taskAssigneeIds\.includes\(assignee\)/);
assert.match(app, /matchesPriority && matchesCreator && matchesAssignee && matchesDate/);
assert.match(app, /creator: document\.getElementById\('taskV2CreatorFilter'\)/);
assert.match(app, /assignee: document\.getElementById\('taskV2AssigneeFilter'\)/);

assert.match(app, /if \(dropdown\?\.parentElement !== document\.body\) document\.body\.appendChild\(dropdown\)/);
assert.match(app, /requestAnimationFrame\(\(\) => dropdown\.querySelector\('\.task-watcher-search'\)\?\.focus\(\)\)/);
assert.match(app, /window\.closeTaskWatcherDropdown\?\.\('taskWatchers'\)/);
assert.match(css, /body > \.task-watcher-dropdown\.multi-select-modal-layer[\s\S]*z-index: 2147483600 !important/);
assert.match(css, /\.task-v2-person-filter[\s\S]*width: 150px !important/);

console.log('Watcher picker stacks above New Task and task people filters are wired.');
