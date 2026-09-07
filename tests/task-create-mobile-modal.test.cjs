const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');

assert.match(app, /document\.body\.appendChild\(modal\)/);
assert.match(app, /document\.body\.classList\.add\('modal-open', 'create-task-modal-open'\)/);
assert.match(app, /window\.closeCreateTaskModal = function/);
assert.match(app, /document\.body\.classList\.remove\('modal-open', 'create-task-modal-open'\)/);
assert.match(app, /onclick="window\.closeCreateTaskModal\(\)" aria-label="Close"/);
assert.match(css, /body > #createTaskModal \{/);
assert.match(css, /z-index: 2147483200 !important/);
assert.match(css, /body > #createTaskModal \.create-task-modal-content[\s\S]*width: 100% !important;[\s\S]*height: 100% !important;/);
assert.match(css, /body\.create-task-modal-open \.sidebar[\s\S]*visibility: hidden !important/);
assert.match(css, /body > #createTaskModal \.create-task-body[\s\S]*overflow-y: auto !important/);
assert.match(css, /body > #createTaskModal #standardTaskForm > \.create-task-footer[\s\S]*width: 100%;[\s\S]*margin: 0 !important/);

console.log('New Task modal is portaled and constrained to the mobile viewport.');
