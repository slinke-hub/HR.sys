const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const phase1 = fs.readFileSync(path.join(root, 'supabase/migrations/20261002090000_project_operations_phase_1.sql'), 'utf8');

const accessViewStart = app.indexOf('async function canCurrentUserAccessView(viewId)');
const sidebarStart = app.indexOf('window.updateSidebarVisibility = async function ()');
const projectsStart = app.indexOf('async function renderProjects()');
const detailStart = app.indexOf('window.openProjectDetail = async function (id)');
const commandCenterStart = app.indexOf('async function renderProjectCommandCenter()');
assert(accessViewStart >= 0 && sidebarStart > accessViewStart && projectsStart > sidebarStart && detailStart > projectsStart);

const accessView = app.slice(accessViewStart, sidebarStart);
const sidebar = app.slice(sidebarStart, projectsStart);
const openDetail = app.slice(detailStart, app.indexOf('// ==========================================', detailStart));
const commandCenter = app.slice(commandCenterStart, app.indexOf('function canViewFullProjectCommandCenter', commandCenterStart));

assert.match(db, /rpc\('list_accessible_projects_secure'\)/, 'Project membership must be decided by the scoped secure list RPC');
assert.match(db, /rpc\('get_project_detail_secure',\s*\{\s*p_project_id:\s*projectId\s*\}\)/, 'Project detail must use the secure detail RPC');
assert.match(accessView, /async function hasAccessibleProjectMembership\([\s\S]*?db\.fetchProjects\(\)[\s\S]*?projects\.some\(project => !!project\?\.id\)/);
assert.match(accessView, /if \(await hasAccessibleProjectMembership\(\)\) return true/, 'Scoped Project membership should grant the Projects page, not Command Center');
assert.match(accessView, /const detail = await db\.fetchProjectDetails\(projectId\)[\s\S]*?detail\?\.success[\s\S]*?detail\.data\?\.project\?\.id/, 'Specific Project routes must ask the secure detail RPC');
assert.match(accessView, /new Set\(\['dashboard', 'requests', 'time', 'tasks', 'documents', 'profile'\]\)\.has\(viewId\)/, 'Unassigned employees do not gain Projects through the default Employee allowlist');
assert.match(sidebar, /const hasProjectMembership = [\s\S]*?await hasAccessibleProjectMembership\(\)/);
assert.match(sidebar, /canUseProjectPages = canUseMarketingPages \|\| managerProjectAccess \|\| canViewFullProjectCommandCenter\(\) \|\| hasProjectMembership/);
assert.match(sidebar, /projectsNav\.forEach\(item => \{ item\.style\.display = canUseProjectPages \? 'flex' : 'none'; \}\)/, 'Desktop and mobile navigation share the scoped Projects visibility');
assert.match(openDetail, /const detailResult = usePreAuthorized[\s\S]*?: await db\.fetchProjectDetails\(id\)/);
assert.doesNotMatch(openDetail.slice(0, openDetail.indexOf('const detailResult')), /canViewFullProjectCommandCenter/, 'Do not deny assigned Project members before the backend detail RPC decides');
assert.match(openDetail, /if \(!canViewFullProjectCommandCenter\(\)\) return openAssignedProjectTodoDetail\(id\)/, 'Preserve the narrower assigned-To-Do fallback after a denied detail RPC');
assert.match(app, /viewId === 'project-command-center'\) return canViewFullProjectCommandCenter\(\)/, 'Command Center route must retain its separate admin gate');
assert.match(commandCenter, /if \(!currentUser \|\| !canViewFullProjectCommandCenter\(\)\)/, 'Command Center renderer must retain its separate admin gate');
assert.match(app, /if \(directProjectId && !route\.get\('todo'\)\) void window\.openProjectDetail\(directProjectId\)/, 'Direct Project URLs open the detail after route authorization');
assert.match(phase1, /IF v_user IS NULL OR NOT public\.is_project_portfolio_admin\(v_user\) THEN[\s\S]*?Project command center access denied/);
assert.match(phase1, /WHERE auth\.uid\(\) IS NOT NULL AND public\.can_access_project\(project\.id, auth\.uid\(\)\)/, 'Project list must remain scoped to backend membership');
assert.match(phase1, /IF v_user IS NULL OR NOT public\.can_access_project\(p_project_id, v_user\) THEN[\s\S]*?Project not found or access denied/, 'Project detail remains backend-authorized');
assert.match(phase1, /'budget_amount', CASE WHEN v_can_financial THEN[\s\S]*?'actual_cost', CASE WHEN v_can_financial THEN/, 'Secure detail RPC must retain financial redaction');
assert.match(app, /const canViewFinancials = canCurrentUserViewBusinessFinancials\(\)/, 'Project detail financial display remains permission-gated');
assert.match(app, /const candidates = \[\.\.\.document\.querySelectorAll\('\.sidebar-nav > \.nav-item\[data-view\]'\)\][\s\S]*?item\.style\.display !== 'none'[\s\S]*?canCurrentUserAccessView\(item\.dataset\.view\)/, 'Mobile More menu must use the same visible items and route guard');
assert.match(html, /data-i18n="nav_projects"/, 'Existing localized Projects labels remain in the shared desktop/mobile navigation');

console.log('Assigned Project member frontend access contract: PASS');
