const assert = require('node:assert/strict');
const fs = require('node:fs');

const css = fs.readFileSync('css/components.css', 'utf8');
const app = fs.readFileSync('js/app.js', 'utf8');

const overlayRule = css.match(/\.side-panel-overlay\s*\{([\s\S]*?)\}/);
const panelRule = css.match(/\.side-panel\s*\{([\s\S]*?)\}/);
assert.ok(overlayRule, 'Task detail overlay rule is missing');
assert.ok(panelRule, 'Task detail panel rule is missing');

const overlayZIndex = Number(overlayRule[1].match(/z-index:\s*(\d+)/)?.[1]);
const panelZIndex = Number(panelRule[1].match(/z-index:\s*(\d+)/)?.[1]);
assert.ok(Number.isFinite(overlayZIndex), 'Task detail overlay z-index is missing');
assert.ok(Number.isFinite(panelZIndex), 'Task detail panel z-index is missing');
assert.ok(panelZIndex > overlayZIndex, 'Task detail panel must stack above its overlay');
assert.match(panelRule[1], /pointer-events:\s*auto/);

assert.match(app, /class=\"btn btn-primary task-detail-handoff\"/);
assert.match(app, /window\.handleCompleteAndHandOffTask\('\$\{task\.id\}'\)/);
assert.match(app, /class=\"btn btn-primary task-detail-edit\"/);
assert.match(app, /openEditTaskModal\(document\.getElementById\('detailsTaskId'\)\.value\)/);

console.log('Task detail actions remain above the backdrop and retain their handlers.');
