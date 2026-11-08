const assert = require('node:assert/strict');
const fs = require('node:fs');

const app = fs.readFileSync('js/app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

assert.match(app, /window\.openArchivedTaskDetails\s*=\s*async function\s*\(taskId\)[\s\S]*?await window\.openTaskDetailsModal\(String\(taskId\)\)/);
assert.match(app, /if\s*\(!\['tasks',\s*'tasks_v2',\s*'archived_tasks'\]\.includes\(currentView\)\)\s*\{\s*await renderView\('tasks'\);/);
assert.match(html, /id="taskSidePanel"/);
assert.match(html, /id="taskSidePanelOverlay"/);

console.log('Archived task details stay open over the archived tasks view.');
