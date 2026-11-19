/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const css = fs.readFileSync(path.join(root, 'css', 'task-manager-mobile-final.css'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');

assert.match(css, /@media \(max-width: 900px\)[\s\S]*\.task-v2-shell \.task-pipeline-card-footer\s*\{[\s\S]*display: grid/);
assert.match(css, /task-stage-select-wrap[\s\S]*grid-column: 1 \/ -1/);
assert.match(css, /task-stage-select[\s\S]*width: 100%/);
assert.match(css, /task-card-progress-action[\s\S]*width: 100%/);
assert.match(css, /task-card-signals[\s\S]*justify-content: space-between/);
assert.match(app, /class="task-pipeline-card-footer"/);
assert.match(app, /class="task-stage-select-wrap"/);
assert.match(app, /class="task-card-signals"/);

console.log('task-pipeline-responsive: PASS');
