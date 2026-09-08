/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, '..', 'css', 'components.css'), 'utf8');
const start = source.indexOf('function closeTaskContextMenu()');
const end = source.indexOf('\nasync function renderTasksV2()', start);
assert.ok(start >= 0 && end > start, 'Task context-menu implementation was not found');

const menuSource = source.slice(start, end);
assert.match(menuSource, /window\.handleTaskContextMenu = function/);
assert.match(menuSource, /editItem\.hidden = !canEdit/);
assert.match(menuSource, /deleteItem\.hidden = !canDelete/);
assert.match(menuSource, /window\.openEditTaskModal\(taskId\)/);
assert.match(menuSource, /window\.handleDeleteTask\(taskId\)/);
assert.match(menuSource, /Math\.min\(event\.clientX, window\.innerWidth - menuRect\.width/);
assert.match(menuSource, /Math\.min\(event\.clientY, window\.innerHeight - menuRect\.height/);
assert.match(menuSource, /event\.key === 'Escape'/);
assert.match(css, /\.custom-context-menu \{[\s\S]*background: #ffffff !important/);
assert.match(css, /\.custom-context-menu \{[\s\S]*opacity: 1 !important/);
assert.match(css, /\[data-theme="dark"\] \.custom-context-menu/);

console.log('Task context-menu tests passed.');
