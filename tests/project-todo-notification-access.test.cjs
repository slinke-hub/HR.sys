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
const lookupFixMigration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260914102000_fix_assigned_project_todo_lookup.sql'), 'utf8');
const projectAssigneeAccessMigration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260915150000_project_assignment_directory_and_access.sql'), 'utf8');

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
assert.match(lookupFixMigration, /LANGUAGE SQL[\s\S]*?SECURITY DEFINER/);
assert.match(lookupFixMigration, /project\.project_name::TEXT/);
assert.match(lookupFixMigration, /assigned_todo\.title::TEXT/);
assert.match(lookupFixMigration, /requested_todo\.id = p_todo_id[\s\S]*?auth\.uid\(\) = ANY/);
assert.match(projectAssigneeAccessMigration, /CREATE OR REPLACE FUNCTION public\.list_active_project_assignment_employees/);
assert.match(projectAssigneeAccessMigration, /CREATE OR REPLACE FUNCTION public\.list_accessible_project_profiles/);
assert.match(projectAssigneeAccessMigration, /NOT public\.can_access_crm\(auth\.uid\(\)\)/);
assert.match(projectAssigneeAccessMigration, /p_user_id = ANY\(COALESCE\(project\.assigned_people/);
assert.match(projectAssigneeAccessMigration, /auth\.uid\(\) = ANY\(COALESCE\(assigned_people/);

assert.match(db, /async fetchAssignedProjectTodoContext\(/);
assert.match(db, /rpc\('fetch_assigned_project_todo_context'/);
assert.match(db, /async fetchProjectAssignmentEmployees\(/);
assert.match(db, /rpc\('list_active_project_assignment_employees'/);
assert.match(db, /async fetchAccessibleProjectProfiles\(/);
assert.match(db, /rpc\('list_accessible_project_profiles'/);
assert.match(db, /async addProjectTodo\([\s\S]*?flushTaskNotificationEmails\(\)/);

assert.match(app, /window\.openProjectTodoNotification = async function/);
assert.match(app, /openAssignedProjectTodoDetail/);
assert.match(app, /project\?\.assigned_people\?\.includes\(currentUser\?\.id\)/);
assert.match(app, /if \(!canViewFullProjectCommandCenter\(currentUserProfile, project\)\) return openAssignedProjectTodoDetail\(id\)/);
assert.match(app, /db\.fetchProjectAssignmentEmployees\(\)/);
assert.match(app, /db\.fetchAccessibleProjectProfiles\(\)/);
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

console.log('Project assignees receive full project access while To-Do-only assignees keep a restricted view.');
