const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const data = fs.readFileSync(path.join(root, 'js', 'data.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

function assert(condition, message) {
    if (!condition) throw new Error(message);
}

assert(app.includes('id="taskDue" class="form-control" min="${todayDate}" required'), 'new task due date is required in the form');
assert(app.includes("Please select a due date.") && app.includes("يرجى تحديد تاريخ التسليم"), 'new task due date is validated in both languages');
for (const id of ['taskPriority', 'taskEstimate', 'taskVisibility', 'taskTags']) {
    assert(app.includes(`id="${id}"`), `new task modal includes ${id}`);
}
assert(app.includes("const estimatedTime = document.getElementById('taskEstimate')?.value.trim() || null;"), 'estimated time is read from the form');
assert(app.includes("const tags = String(document.getElementById('taskTags')?.value || '')"), 'tags are normalized from comma-separated input');
assert(app.includes('priority, \'General\', titleI18n, {}, null, null, estimatedTime, visibility, projectId, tags'), 'new task sends priority, estimate, privacy, and tags');
assert(app.includes('const managerId = department.head_id || department.manager_id;'), 'department manager is included in the assignment options');
assert(app.includes("modal.dataset.editTab = 'combined';"), 'edit modal uses a combined details state');
assert(index.includes('class="edit-task-scroll-body"') && index.includes('id="editTaskTabAdvanced"') && index.includes('display: flex'), 'edit modal renders advanced fields in the same scrollable form');
assert(!index.includes('class="edit-task-tabs"'), 'edit modal tabs are removed');
assert(data.includes('ui_dates: "Due Date"') && data.includes('ui_dates: "تاريخ التسليم"'), 'Dates label is localized as Due Date');

console.log('task-creation-edit-workflow: PASS');
