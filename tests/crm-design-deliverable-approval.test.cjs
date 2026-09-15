/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const app = read('js/app.js');
const db = read('js/db.js');
const css = read('css/components.css');
const migration = read('supabase/migrations/20260914113000_crm_design_deliverable_approval.sql');
const originalWorkflowMigration = read('supabase/migrations/20260909110000_crm_presentation_order_workflow.sql');

for (const id of [
  'crmDesignCompletionModal', 'crmDesignCompletionForm', 'crmDesignCompletionTaskId',
  'crmDesignCompletionFiles', 'crmDesignCompletionSelection', 'crmDesignCompletionSubmit'
]) assert.match(html, new RegExp(`id="${id}"`), `Missing Design completion field ${id}`);

assert.match(html, /id="crmDesignCompletionFiles"[^>]*accept="application\/pdf,image\/\*"[^>]*multiple/);
assert.match(app, /window\.openCrmDesignCompletionModal = function/);
assert.match(app, /window\.handleCrmDesignCompletionSubmit = async function/);
assert.match(app, /crm_workflow_kind === 'QUOTE_PROPOSAL_DESIGN'/);
assert.match(app, /status === 'completed'[\s\S]*openCrmDesignCompletionModal\(task\)/);
assert.match(app, /db\.uploadTaskAttachment\(task\.id, currentUser\.id, file\)/);
assert.match(app, /submission_links: uploadedReferences/);
assert.match(app, /window\.removeCrmDesignCompletionFile = function/);
assert.match(app, /db\.addTaskComment\([\s\S]*Completed Design files submitted for CRM approval\./);
assert.match(app, /window\.handleCrmDesignAdminApproveAll = async function/);
assert.match(app, /db\.decideCrmDesignTaskApprovals\(pending\.map\(step => step\.id\), 'APPROVED'/);
assert.match(app, /crm-design-review-files/);
assert.match(app, /Completed Design files/);
assert.match(app, /openDealImagePreview\(this\)/);
assert.match(app, /notification\.event_type === 'crm_design_task_approval_requested'[\s\S]*renderView\('approvals'\)[\s\S]*setApprovalsTab\?\.\('crm'\)[\s\S]*openDealWorkflowModal/);

assert.match(db, /tasks'\)\.select\('id, title, status, submission_links, completion_requested_at'\)/);
assert.match(db, /task_attachments'[\s\S]*\.in\('file_url', submissionReferences\)/);
assert.match(db, /designFiles/);
assert.match(db, /async decideCrmDesignTaskApprovals\(stepIds, decision/);

assert.match(migration, /cardinality\(NEW\.submission_links\)/);
assert.match(migration, /NEW\.status := 'Pending Approval'/);
assert.match(migration, /crm_design_task_approval_steps/);
assert.match(migration, /crm_deal_approval_steps/);
assert.match(migration, /crm_design_task_approval_requested/);
assert.match(migration, /task_email_outbox/);
assert.match(migration, /attachment_links/);
assert.match(originalWorkflowMigration, /UPDATE public\.tasks SET status = 'in_progress'/);
assert.match(originalWorkflowMigration, /UPDATE public\.crm_deals SET stage = 'NEGOTIATION'/);
assert.match(originalWorkflowMigration, /A rejection reason is required/);

assert.match(css, /\.crm-design-completion-modal/);
assert.match(css, /\.crm-design-completion-remove/);
assert.match(css, /\.crm-admin-approve-all/);
assert.match(css, /\.crm-design-review-grid/);
assert.match(css, /height: clamp\(220px, 30vw, 380px\)/);

console.log('CRM Design deliverable submission and approval loop tests passed.');
