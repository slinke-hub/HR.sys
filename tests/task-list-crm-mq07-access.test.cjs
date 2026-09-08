const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const crm = fs.readFileSync(path.join(root, 'src', 'crm-dashboard.jsx'), 'utf8');
const bundle = fs.readFileSync(path.join(root, 'js', 'crm-dashboard.bundle.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260908100000_sales_marketing_crm_and_mq07_design_access.sql'), 'utf8');

assert.match(app, /const selectedScopeTasks = tasks\.filter\(matchesSelectedTaskScope\)/);
assert.match(app, /data-task-health-total>\$\{selectedScopeTasks\.length\}/);
assert.match(app, /const scopedTasks = tasks\.filter\(matchesSelectedScope\)/);
assert.match(app, /data-task-health-count="waiting"/);
assert.match(app, /panel\.querySelector\('\.task-stage-count'\)/);
assert.match(app, /return normalizedStage === stage && matchesFilters\(task\)/);
assert.match(app, /window\.filterTasksV2\?\.\(\);\s*\n};\s*\n\s*window\.openEditTaskModal/);
assert.match(css, /\.task-v2-lists \.task-count-badge \{[\s\S]*position: static !important;[\s\S]*margin-inline-start: auto !important;/);

assert.match(app, /async function canCurrentUserUseCRM\(\)/);
assert.match(app, /\(SALES\|MARKETING\)/);
assert.match(app, /المبيعات\|التسويق/);
assert.match(app, /if \(viewId === 'crm'\) return canCurrentUserUseCRM\(\)/);
assert.match(app, /const canUseMarketingPages = await canCurrentUserUseCRM\(\)/);
assert.match(app, /canInteractCrm: await canCurrentUserUseCRM\(\)/);
assert.match(crm, /payload\.canInteractCrm === true/);
assert.match(bundle, /canInteractCrm/);

assert.match(app, /const isMq07Profile = .*emp_index.*=== 7/);
assert.match(app, /const canMq07UseDesignTaskList/);
assert.match(app, /user\.department_id === currentUserProfile\?\.department_id/);
assert.match(app, /Design tasks can only be assigned within your department/);

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.can_access_crm/);
assert.match(migration, /CREATE POLICY crm_authorized_deals_all/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.is_mq07_design_list/);
assert.match(migration, /profile\.emp_index = 7/);
assert.match(migration, /CREATE POLICY mq07_design_tasks_update_own/);
assert.match(migration, /created_by = auth\.uid\(\)/);
assert.match(migration, /CREATE TRIGGER enforce_mq07_design_assignment_department_trigger/);
assert.match(migration, /assignee\.department_id IS DISTINCT FROM caller_department/);

console.log('Task-list counters, CRM roles, and MQ-07 Design access are scoped correctly.');
