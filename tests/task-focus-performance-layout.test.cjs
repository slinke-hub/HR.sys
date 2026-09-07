/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const layout = fs.readFileSync(path.join(root, 'css', 'layout.css'), 'utf8').replace(/\r\n/g, '\n');
const components = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8').replace(/\r\n/g, '\n');

assert.match(app, /const usersById = new Map\(\(allUsers \|\| \[\]\)\.map/);
assert.match(app, /const taskChildrenByParentId = new Map\(\)/);
assert.match(app, /orderedFocusTasks\.map\(task =>/);
assert.match(app, /data-parent-task-id="\$\{task\.parent_task_id \|\| ''\}"/);
assert.match(app, /visibleFocusRoots\.has\(rootTaskId\(task\)\)/);
assert.match(app, /if \(content === previousContent\) return/);
assert.match(app, /setTimeout\(\(\) => window\.scheduleTaskWorkspaceRefresh\?\.\(0\), 0\)/);

assert.match(components, /Focus view keeps subtasks visibly attached to their main task/);
assert.match(components, /#task-v2-rows-container \.task-v2-subtask-row \.task-v2-row-left/);
assert.match(layout, /Desktop app shell: occupy the viewport exactly/);
assert.match(layout, /@media \(min-width: 901px\)[\s\S]*?\.main-content \{[\s\S]*?height: 100dvh;[\s\S]*?padding: 0;/);
assert.match(layout, /\.view-container \{[\s\S]*?overflow-x: hidden;[\s\S]*?overflow-y: auto;/);

console.log('Task focus grouping, fast refresh, and desktop viewport tests passed.');
