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
for (const status of ['todo', 'in_progress', 'review', 'completed']) {
    assert(index.includes(`data-status="${status}"`), `task details include ${status} progress action`);
}
assert(app.includes('window.handleTaskProgressQuickAction'), 'progress actions use a shared task handler');
assert(app.includes('window.updateTaskProgressQuickActions(task);'), 'task details synchronize progress controls');
assert(app.includes("if (!assignee) {") && app.includes('Please select an assignee.'), 'new task assignee is enforced in the handler');
assert(app.includes('const effectiveAssignee = assignee;'), 'new task creation no longer silently falls back to the creator');
assert(css.includes('.task-progress-quick-actions') && css.includes('grid-template-columns: repeat(4'), 'progress actions have responsive styling');
assert(migration.includes('Task assignee is required') && migration.includes('Task due date is required'), 'database guard enforces required creation fields');
assert(migration.includes('BEFORE INSERT ON public.tasks'), 'database guard only applies to new rows');

console.log('task-details-progress: PASS');
