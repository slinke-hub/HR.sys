/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const css = fs.readFileSync(path.join(root, 'css', 'task-manager-mobile-final.css'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

assert.match(css, /@media \(max-width: 900px\)[\s\S]*\.task-v2-shell \.task-pipeline-card-footer\s*\{[\s\S]*display: grid/);
assert.match(css, /task-pipeline-card-footer\s*\{[\s\S]*grid-template-columns: minmax\(0, 1fr\) !important/);
assert.doesNotMatch(css, /task-card-progress-action/);
assert.match(css, /task-card-signals[\s\S]*justify-content: space-between/);
assert.match(app, /class="task-pipeline-card-footer"/);
assert.match(app, /class="task-card-signals"/);
assert.doesNotMatch(app, /task-card-progress-action|progressCardAction/);
const pipelineRenderer = app.slice(app.indexOf('function renderTaskCard('), app.indexOf('function closeTaskContextMenu('));
assert.doesNotMatch(pipelineRenderer, /task-stage-select|<select/);
assert.match(pipelineRenderer, /task-assignee-full-name/);
assert.match(pipelineRenderer, /task-creator-full-name/);
assert.match(app, /class="task-v2-stage-select/);
assert.match(index, /css\/task-manager-mobile-final\.css\?v=2026111904/);

console.log('task-pipeline-responsive: PASS');
