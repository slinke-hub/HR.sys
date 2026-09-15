/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const app = read('js/app.js');
const css = read('css/components.css');
const html = read('index.html');
const worker = read('sw.js');
const db = read('js/db.js');
const dashboard = read('src/crm-dashboard.jsx');

assert.match(app, /const isMq08Profile = .*emp_index\) === 8/s);
assert.match(app, /function canMq08ChangeCrmDesignDealStatus\(task\)/);
assert.match(app, /task\.crm_workflow_kind !== 'QUOTE_PROPOSAL_DESIGN'/);
assert.match(app, /id="crmDesignDealStatusSelect"/);
assert.match(app, /IN_PROGRESS[\s\S]*LATE[\s\S]*COMPLETED/);
assert.match(app, /window\.handleCrmDesignDealStatusChange = async function/);
assert.match(app, /IN_PROGRESS: 'in_progress'[\s\S]*LATE: 'late'[\s\S]*COMPLETED: 'completed'/);
assert.match(app, /window\.taskV2ChangeStage\(taskId, requestedTaskStatus\)/);
assert.match(app, /window\.refreshCrmDashboardInBackground/);
assert.match(html, /id="dealWorkflowDesignTaskStatus"/);
assert.match(app, /function renderDealWorkflowDesignTaskStatus\(workflow, isMq08Viewer\)/);
assert.match(app, /id="dealWorkflowDesignTaskStatusSelect"/);
assert.match(app, /window\.handleDealWorkflowDesignTaskStatusChange = async function/);
assert.match(app, /window\.taskV2ChangeStage\(task\.id, taskStatus\)/);
assert.match(app, /Complete · Waiting for approval/);
assert.match(db, /completion_requested_at, crm_workflow_kind, crm_deal_id, assignee_id, assignee_ids/);
assert.match(dashboard, /designInProgress: 'In progress'/);
assert.match(dashboard, /designCompleted: 'Complete · Waiting for approval'/);
assert.match(dashboard, /designInProgress, classes: 'tw-bg-amber-50 tw-text-amber-700/);
assert.match(dashboard, /designCompleted, classes: 'tw-bg-emerald-50 tw-text-emerald-700/);
assert.match(css, /\.task-crm-design-status-control/);
assert.match(css, /\.task-crm-design-status-select/);
assert.match(css, /\.deal-workflow-design-status-actions/);
assert.match(html, /css\/components\.css\?v=2026091507/);
assert.match(html, /js\/db\.js\?v=2026091508/);
assert.match(html, /js\/crm-dashboard\.bundle\.js\?v=2026091505/);
assert.match(html, /js\/app\.js\?v=2026091512/);
assert.match(worker, /muqam-hr-mobile-v244/);

console.log('MQ-08 CRM Design task deal-status selector tests passed.');
