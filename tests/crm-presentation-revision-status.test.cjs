/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const app = read('js/app.js');
const db = read('js/db.js');
const source = read('src/crm-dashboard.jsx');
const css = read('css/components.css');
const migration = read('supabase/migrations/20260910150000_crm_presentation_revision_status.sql');
const taskAssetsMigration = read('supabase/migrations/20260910160000_crm_design_task_assets.sql');
const identityMigration = read('supabase/migrations/20260910170000_crm_client_identity_attachments.sql');

assert.match(app, /const submittedAt = deal\.proposal_sent_at \|\| step\.created_at/);
assert.match(app, /deal-presentation-quote-section/);
assert.match(app, /deal-presentation-proposal-section/);
assert.match(app, /deal-presentation-identity-section/);
assert.match(app, /<figcaption>[\s\S]*file\.description/);
assert.match(app, /db\.replaceDealPresentationAttachments\(dealId, currentUser\.id, replacementEntries/);
assert.match(app, /isProposalDesignWorkflow[\s\S]*if \(isProposalDesignWorkflow\) return false/);
assert.match(app, /task\.crm_workflow_kind === 'QUOTE_PROPOSAL_DESIGN'/);
assert.match(app, /\['late','Late'\]/);

assert.match(db, /async replaceDealPresentationAttachments\(dealId, userId, entries, options = \{\}\)/);
assert.match(db, /\.in\('category', replacementCategories\)/);
assert.match(db, /\.delete\(\)[\s\S]*\.in\('id', previousIds\)/);
assert.match(db, /storage\.from\('crm-deal-files'\)\.remove\(previousPaths\)/);
assert.match(db, /\.order\('proposal_sent_at', \{ ascending: false \}\)/);
assert.match(db, /async fetchDealPresentationAttachments\(dealId\)/);
assert.match(db, /\.in\('category', \['QUOTATION', 'CLIENT_IDENTITY', 'PROPOSAL'\]\)/);
assert.match(db, /replaceClientIdentity === true/);

assert.match(app, /task\.crm_workflow_kind === 'QUOTE_PROPOSAL_DESIGN'[\s\S]*db\.fetchDealPresentationAttachments\(task\.crm_deal_id\)/);
assert.match(app, /task-crm-presentation-assets/);
assert.match(app, /task-crm-proposal-gallery/);
assert.match(app, /crmClientIdentityFiles/);
assert.match(app, /data-image-description="\$\{escapeHTML\(file\.description \|\| ''\)\}"/);

assert.match(source, /designTaskStatus/);
assert.match(source, /designIsLate/);
assert.match(source, /designCompleted/);
assert.match(source, /normalizeStage\(deal\.stage\) === 'PRESENTATION' && deal\.design_task_id/);
assert.match(css, /\.deal-attachment-section/);
assert.match(css, /\.task-crm-presentation-assets/);
assert.match(css, /\.task-crm-proposal-gallery figcaption/);

assert.match(migration, /ADD COLUMN IF NOT EXISTS design_task_status text/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.sync_crm_design_task_status/);
assert.match(migration, /WHEN LOWER\(BTRIM\(COALESCE\(NEW\.status, ''\)\)\) = 'late' THEN 'LATE'/);
assert.match(migration, /stage = 'PITCH',[\s\S]*design_task_status = 'IN_PROGRESS'/);
assert.match(migration, /PERFORM public\.create_crm_design_task_for_deal\(v_deal\.id\)/);
assert.match(migration, /ELSE[\s\S]*workflow_status = 'APPROVED', stage = 'NEGOTIATION'/);
assert.match(migration, /Repair quote-and-proposal deals/);
assert.match(taskAssetsMigration, /CREATE POLICY crm_authorized_attachments_select/);
assert.match(taskAssetsMigration, /task\.crm_deal_id = crm_deal_attachments\.deal_id/);
assert.match(taskAssetsMigration, /task\.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'/);
assert.match(taskAssetsMigration, /auth\.uid\(\) IN \(task\.assignee_id, task\.created_by\)/);
assert.match(identityMigration, /ADD CONSTRAINT crm_deal_attachments_category_check/);
assert.match(identityMigration, /'CLIENT_IDENTITY'/);

console.log('CRM presentation revisions, asset replacement, and Design status checks passed.');
