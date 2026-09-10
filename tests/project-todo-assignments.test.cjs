const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260909140000_project_todo_assignments.sql'), 'utf8');

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.project_todos/);
assert.match(migration, /due_at TIMESTAMPTZ NOT NULL/);
assert.match(migration, /assignee_ids UUID\[\] NOT NULL/);
assert.match(migration, /CARDINALITY\(assignee_ids\) > 0/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.can_manage_project_todos/);
assert.match(migration, /OPERATIONS MANAGER/);
assert.match(migration, /مدير العمليات/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.is_project_todo_assignee_eligible/);
assert.match(migration, /marketing\|sales\|operations\?/);
assert.match(migration, /التسويق\|المبيعات\|العمليات/);
assert.match(migration, /Every assignee must be an active Marketing, Sales, or Operations employee/);
assert.match(migration, /auth\.uid\(\) = ANY\(COALESCE\(todo_row\.assignee_ids/);
assert.match(migration, /REVOKE ALL ON public\.project_todos FROM PUBLIC, authenticated/);
assert.match(migration, /GRANT SELECT ON public\.project_todos TO authenticated/);
assert.match(migration, /ALTER PUBLICATION supabase_realtime ADD TABLE public\.project_todos/);

for (const method of ['fetchProjectTodos', 'addProjectTodo', 'setProjectTodoCompleted', 'deleteProjectTodo']) {
  assert.match(db, new RegExp(`async ${method}\\(`), `Missing project To Do DB method: ${method}`);
}
assert.match(db, /rpc\('add_project_todo'/);
assert.match(db, /p_assignee_ids: assigneeIds/);
assert.match(db, /rpc\('set_project_todo_completed'/);
assert.match(db, /rpc\('delete_project_todo'/);

assert.match(app, /Project To Do list/);
assert.match(app, /قائمة مهام المشروع/);
assert.match(app, /type="datetime-local"/);
assert.match(app, /id="projectTodoAssignees"[^>]*multiple required/);
assert.match(app, /selectedOptions/);
assert.match(app, /assigneeIds\.includes\(currentUser\?\.id\)/);
assert.match(app, /projectTodoAssigneeOptions/);
assert.match(app, /projectPortfolioDepartments/);
assert.match(app, /marketing\|sales\|operations\?/);
assert.match(app, /db\.fetchDepartments\(\)/);
assert.match(app, /isOperationsManagerProjectProfile/);
assert.match(app, /window\.addProjectTodo/);
assert.match(app, /window\.toggleProjectTodo/);
assert.match(app, /window\.deleteProjectTodo/);
assert.match(app, /table: 'project_todos'/);
assert.match(app, /Promise\.all\(\[db\.fetchProjectUpdates\(id\), db\.fetchProjectTodos\(id\)\]\)/);

assert.match(css, /\.project-todo-form/);
assert.match(css, /\.project-todo-item\.is-overdue/);
assert.match(css, /@container \(max-width:560px\)[^}]*[\s\S]*?\.project-todo-form \{ grid-template-columns:1fr; \}/);
assert.match(html, /css\/components\.css\?v=2026091016/);
assert.match(html, /js\/db\.js\?v=2026091010/);
assert.match(html, /js\/app\.js\?v=2026091015/);

console.log('Project To Do assignments are scoped, bilingual, deadline-aware, responsive, and independent from Tasks Manager.');
