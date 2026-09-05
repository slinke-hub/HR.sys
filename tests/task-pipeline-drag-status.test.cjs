/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const start = source.indexOf('window.handleTaskDrop = async function');
const end = source.indexOf('\nwindow.openEditTaskModal', start);
assert.ok(start >= 0 && end > start, 'Task drag-and-drop handler was not found');

const handlerSource = source.slice(start, end);
assert.match(handlerSource, /const stageSelect = taskCard\.querySelector\('\.task-v2-stage-select'\)/);
assert.match(handlerSource, /stageSelect\.value = actualStatus/);
assert.match(handlerSource, /const savedStatus = result\.status \|\| finalStatus/);
assert.match(handlerSource, /savedStageSelect\.value = savedStatus/);
assert.match(handlerSource, /if \(window\.taskCache\?\.\[id\]\) window\.taskCache\[id\]\.status = savedStatus/);
assert.match(handlerSource, /if \(result\?\.error\)[\s\S]*await renderView/);

console.log('Task pipeline drag-status tests passed.');
