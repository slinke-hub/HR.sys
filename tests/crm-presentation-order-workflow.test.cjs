/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const app = read('js/app.js');
const db = read('js/db.js');
const source = read('src/crm-dashboard.jsx');
const css = read('css/components.css');
const migration = read('supabase/migrations/20260909110000_crm_presentation_order_workflow.sql');
const autoDiscussionMigration = read('supabase/migrations/20260910110000_crm_approved_deals_auto_discussion.sql');

for (const id of [
  'crmPresentationChoiceModal', 'crmPresentationRequestModal', 'presentationQuoteFile',
  'presentationProposalDescriptions', 'crmOrderModal',
  'orderEmployeeName', 'orderEventDate', 'orderEventStartTime', 'orderInstallationTime',
  'orderUninstallationTime', 'orderClientName', 'orderClientCompany', 'orderClientEmail',
  'orderClientPhone', 'orderLocationUrl', 'orderLocationText', 'orderProjectAssignees',
  'orderEquipmentList'
]) assert.match(html, new RegExp(`id="${id}"`), `Missing workflow field ${id}`);

for (const id of [
  'dealAttachmentCategory', 'dealQuoteUploadSection', 'dealQuoteUploadRows',
  'dealProposalUploadSection', 'dealProposalUploadRows', 'dealAttachmentUploadButton'
]) assert.match(html, new RegExp(`id="${id}"`), `Missing multi-file upload field ${id}`);

assert.match(html, /name="orderInstallationType" value="INDOOR"/);
assert.match(html, /name="orderInstallationType" value="OUTDOOR"/);
assert.match(html, /name="orderInstallationType" value="INDOOR_OUTDOOR"/);
assert.match(html, /crm-add-proposal-image[^>]*onclick="addProposalImageRow\(\)"/);
assert.match(html, /id="addProposalImageButton"[^>]*aria-controls="presentationProposalDescriptions"/);
assert.match(html, /id="presentationProposalDescriptions"[\s\S]*id="addProposalImageButton"/);
assert.match(html, /id="dealAttachmentCategory"[\s\S]*value="QUOTATION"[\s\S]*value="PROPOSAL"[\s\S]*value="QUOTE_PROPOSAL"/);
assert.doesNotMatch(html.match(/<select id="dealAttachmentCategory"[\s\S]*?<\/select>/)?.[0] || '', /TECHNICAL_PRESENTATION|PHOTO|OTHER/);
assert.match(html, /onclick="addDealQuoteUploadRow\(\)"/);
assert.match(html, /onclick="addDealProposalUploadRow\(\)"/);
assert.match(source, /requiresDetails = \['PITCH', 'WON', 'LOST'\]/);
assert.match(app, /newStage === 'PITCH'.*openCrmPresentationChoiceModal/s);
assert.match(app, /window\.addProposalImageRow = function/);
assert.match(app, /scrollIntoView\(\{ behavior: 'smooth', block: 'nearest' \}\)/);
assert.match(app, /window\.addProposalImageRow\(false\)/);
assert.match(app, /window\.updateDealAttachmentUploadType = function/);
assert.match(app, /window\.addDealQuoteUploadRow = function/);
assert.match(app, /window\.addDealProposalUploadRow = function/);
assert.match(app, /needsQuote = uploadType === 'QUOTATION' \|\| uploadType === 'QUOTE_PROPOSAL'/);
assert.match(app, /needsProposal = uploadType === 'PROPOSAL' \|\| uploadType === 'QUOTE_PROPOSAL'/);
assert.match(app, /proposalEntries\.some\(entry => !entry\.description\)/);
assert.match(app, /data-proposal-image-row/);
assert.match(app, /data-proposal-file/);
assert.match(app, /data-proposal-description/);
assert.match(app, /proposalEntries\.some\(entry => !entry\.description\)/);
assert.match(app, /id="dealPresentationAssetsSummary"/);
assert.match(app, /function renderDealPresentationAssets\(attachments\)/);
assert.match(app, /category \|\| ''\)\.toUpperCase\(\) === 'QUOTATION'/);
assert.match(app, /category \|\| ''\)\.toUpperCase\(\) === 'PROPOSAL'/);
assert.match(app, /deal-presentation-image-card/);
assert.match(app, /<figcaption>[\s\S]*file\.description/);
assert.match(app, /db\.startCrmPresentationApproval\(dealId, requestType\)/);
assert.match(app, /db\.decideCrmDesignTaskApproval/);
assert.match(app, /function areDealApprovalsComplete\(workflow\)/);
assert.match(app, /async function ensureApprovedDealIsInDiscussion\(deal, workflow\)/);
assert.match(app, /await ensureApprovedDealIsInDiscussion\(deal, workflow\)/);
assert.doesNotMatch(app, /allApproved\s*&&[^\n]*approval_type\s*!==\s*'QUOTE_PROPOSAL'/);
assert.doesNotMatch(app, /crm_approval_note_prompt/, 'Approving CRM requests must not open an optional note prompt');
assert.match(app, /decision === 'REJECTED'[\s\S]*showPromptModal[\s\S]*crm_rejection_note_prompt/);
assert.match(app, /db\.createProjectFromWonDealV2\(orderData, dealId\)/);
assert.match(app, /task\?\.crm_workflow_kind === 'QUOTE_PROPOSAL_DESIGN'/);
assert.match(app, /updateResult\?\.data\?\.status \|\| actualStatus/);
assert.match(app, /max-height:360px|deal-attachment-image/s);
assert.match(css, /\.deal-attachment-item\.deal-attachment-image img/);
assert.match(css, /max-height: 360px/);
assert.match(css, /\.deal-presentation-image-link img[\s\S]*height: clamp\(280px, 42vw, 520px\)/);
assert.match(css, /\.deal-presentation-image-card figcaption/);
assert.match(css, /\.deal-attachment-upload-section\[hidden\]\s*\{\s*display:\s*none;/);
assert.match(css, /\.deal-attachment-upload-row[\s\S]*grid-template-columns: repeat\(2/);
assert.match(css, /\.crm-order-modal/);
assert.match(css, /\.crm-request-file-section\[hidden\]\s*\{\s*display:\s*none;/);
assert.match(css, /max-height: calc\(100dvh - 2rem\)/);

assert.match(db, /async startCrmPresentationApproval\(dealId, requestType\)/);
assert.match(db, /async fetchPendingCrmDesignTaskApprovals\(\)/);
assert.match(db, /async decideCrmDesignTaskApproval\(stepId, decision, note\)/);
assert.match(db, /async createProjectFromWonDealV2\(orderData, dealId\)/);
assert.match(db, /update\(\{ status \}\).*select\('id,status'\)\.single\(\)/s);

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.start_crm_presentation_approval/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS completion_requested_at timestamptz/);
assert.match(migration, /p_request_type = 'QUOTE_PROPOSAL'/);
assert.match(migration, /'CEO'.*'GENERAL_MANAGER'.*'MQ_04'.*'MQ_05'.*'MARKETING_MANAGER'/s);
assert.match(migration, /emp_index = 8/);
assert.match(migration, /crm_workflow_kind.*QUOTE_PROPOSAL_DESIGN/s);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.decide_crm_design_task_approval/);
assert.match(migration, /NEW\.status := 'Pending Approval'/);
assert.match(migration, /NEW\.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'.*RETURN NEW/s);
assert.match(migration, /UPDATE public\.tasks SET status = 'in_progress'/);
assert.match(migration, /UPDATE public\.crm_deals SET stage = 'NEGOTIATION'/);
assert.match(migration, /always_send\).*true/s);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.create_project_from_won_deal_v2/);
assert.match(migration, /client_snapshot.*event_location_text.*installation_type.*equipment/s);

assert.match(autoDiscussionMigration, /CREATE OR REPLACE FUNCTION public\.decide_deal_approval/);
assert.match(autoDiscussionMigration, /SET workflow_status = 'APPROVED', stage = 'NEGOTIATION'/);
assert.match(autoDiscussionMigration, /PERFORM public\.create_crm_design_task_for_deal\(v_deal\.id\)/);
assert.match(autoDiscussionMigration, /Repair deals whose approvals were completed/);

console.log('CRM presentation approvals, Design review, and Won order workflow tests passed.');
