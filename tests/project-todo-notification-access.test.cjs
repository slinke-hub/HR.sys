const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const email = fs.readFileSync(path.join(root, 'supabase', 'functions', 'task-notification-email', 'index.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260914100000_project_todo_assignment_notifications.sql'), 'utf8');
const arabicManagerMigration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260914101000_project_portfolio_arabic_manager_access.sql'), 'utf8');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.notify_project_todo_assignees/);
assert.match(migration, /CREATE TRIGGER project_todo_notify_assignees[\s\S]*?AFTER INSERT ON public\.project_todos/);
assert.match(migration, /'project_todo_assigned'/);
assert.match(migration, /\/?view=projects&project=%s&todo=%s/);
assert.match(migration, /INSERT INTO public\.task_email_outbox/);
assert.match(migration, /TRUE,\s*'PROJECT_TODO'/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.fetch_assigned_project_todo_context/);
assert.match(migration, /auth\.uid\(\) = ANY\(COALESCE\(assigned_todo\.assignee_ids/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.fetch_assigned_project_todo_context\(UUID, UUID\) FROM PUBLIC/);
assert.match(migration, /CREATE POLICY project_portfolio_select[\s\S]*?project_manager_id = auth\.uid\(\)[\s\S]*?is_project_portfolio_admin/);
assert.match(arabicManagerMigration, /job_title_ar[\s\S]*?\(مدير\|مشرف\)/);

assert.match(db, /async fetchAssignedProjectTodoContext\(/);
assert.match(db, /rpc\('fetch_assigned_project_todo_context'/);
assert.match(db, /async addProjectTodo\([\s\S]*?flushTaskNotificationEmails\(\)/);

assert.match(app, /window\.openProjectTodoNotification = async function/);
assert.match(app, /openAssignedProjectTodoDetail/);
assert.match(app, /if \(!canViewFullProjectCommandCenter\(\)\) return openAssignedProjectTodoDetail\(id\)/);
assert.match(app, /project-detail-layout--todo-only/);
assert.match(app, /assignedTodoPrivacy/);
assert.match(app, /notificationNavigationCache = new Map\(\(notifs \|\| \[\]\)/);
assert.match(app, /actionProjectId && actionProjectTodoId/);
assert.match(app, /startupProjectId && startupProjectTodoId/);

assert.match(css, /\.project-assignee-privacy-note/);
assert.match(css, /\.project-detail-layout--todo-only/);

assert.match(email, /item\.context_type === "PROJECT_TODO"/);
assert.match(email, /Open project To-Do/);
assert.match(email, /view=projects&project=/);

console.log('Project To-Do assignment notifications, email links, and restricted assignee views are wired securely.');
