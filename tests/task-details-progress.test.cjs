const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261119110000_task_creation_required_fields.sql'), 'utf8');

function assert(condition, message) {
    if (!condition) throw new Error(message);
}

assert(index.includes('id="detailsTaskCreator"') && index.includes('id="detailsTaskDue"'), 'task details show creator and due date');
assert(!index.includes('taskProgressQuickActions') && !index.includes('task-progress-action'), 'task details omit progress controls');
assert(!app.includes('handleTaskProgressQuickAction') && !app.includes('updateTaskProgressQuickActions'), 'task details do not wire removed progress controls');
assert(!index.includes('editTaskProgress') && !index.includes('editTaskProgressValue') && !app.includes('updateEditTaskProgress'), 'edit task omits the progress slider');
assert(!app.includes('progressCardAction') && !app.includes('syncTaskCardProgressAction'), 'pipeline cards omit progress action');
assert(app.includes("if (!assignee) {") && app.includes('Please select an assignee.'), 'new task assignee is enforced in the handler');
assert(app.includes('const effectiveAssignee = assignee;'), 'new task creation no longer silently falls back to the creator');
assert(!css.includes('.task-progress-quick-actions') && !css.includes('.task-card-progress-action'), 'removed task progress controls have no remaining styles');
assert(css.includes('.edit-task-scroll-body') && css.includes('position: sticky !important'), 'edit modal scroll body and pinned footer are styled');
assert(migration.includes('Task assignee is required') && migration.includes('Task due date is required'), 'database guard enforces required creation fields');
assert(migration.includes('BEFORE INSERT ON public.tasks'), 'database guard only applies to new rows');

console.log('task-details-progress: PASS');
