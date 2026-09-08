const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');

for (const filter of ['waiting', 'active', 'due_this_week', 'overdue']) {
    assert.match(app, new RegExp(`data-task-health-filter="${filter}"`));
    assert.match(app, new RegExp(`setTaskV2HealthFilter\\('${filter}'\\)`));
}

assert.match(app, /window\.setTaskV2HealthFilter = function \(filter\)/);
assert.match(app, /healthFilter === 'waiting'[\s\S]*\['todo', 'Pending Approval'\]\.includes\(task\.status\)/);
assert.match(app, /healthFilter === 'active' && task\.status === 'in_progress'/);
assert.match(app, /healthFilter === 'due_this_week'[\s\S]*daysUntilDue >= 0 && daysUntilDue <= 7/);
assert.match(app, /healthFilter === 'overdue'[\s\S]*dueAt < new Date\(\)/);
assert.match(app, /matchesSearch && matchesStatus && matchesPriority && matchesCreator && matchesAssignee && matchesDate && matchesHealth && matchesProject/);
assert.match(app, /window\.taskV2HealthFilter = 'all'/);
assert.match(css, /\.task-health-item\.active/);
assert.match(css, /\.task-health-item:focus-visible/);
assert.match(app, /class="task-v2-date-control"[\s\S]*id="taskV2DateFilter"/);
assert.match(app, /<input type="date" id="taskV2DateFilter"/);
assert.doesNotMatch(app, /task-v2-date-picker-button/);
assert.doesNotMatch(app, /window\.openTaskV2DatePicker/);
assert.match(css, /\.task-v2-date-control \{/);
assert.doesNotMatch(css, /\.task-v2-date-picker-button \{/);
assert.match(app, /const ownTaskLists = taskLists\.filter/);
assert.match(app, /personalListItems \+= ownTaskLists\.map/);

console.log('Task pipeline health chips act as accessible, composable filters.');
