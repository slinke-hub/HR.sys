/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const dashboard = read('src/crm-dashboard.jsx');
const app = read('js/app.js');
const db = read('js/db.js');
const stageMigration = read('supabase/migrations/20260905130000_crm_pipeline_stages.sql');
const workflowMigration = read('supabase/migrations/20260917090000_shared_business_logic_services.sql');

// Keep the established pipeline states distinct and retain historical values.
assert.match(dashboard, /key: 'DISCUSSION', dbStage: 'NEGOTIATION'/);
assert.match(dashboard, /if \(value === 'NEGOTIATION'\) return 'DISCUSSION'/);
assert.match(dashboard, /key: 'WON', dbStage: 'WON'/);
assert.match(dashboard, /key: 'LOST', dbStage: 'LOST'/);
assert.match(stageMigration, /'NEGOTIATION', 'WON', 'LOST'/);
assert.match(app, /'PITCH', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST'/);

// Approval remains a required transition gate for Negotiation and Won.
assert.match(dashboard, /\['NEGOTIATION', 'WON'\]\.includes\(stage\.dbStage\)/);
assert.match(app, /ensureApprovedDealIsInDiscussion/);
assert.match(workflowMigration, /CREATE OR REPLACE FUNCTION public\.start_deal_approval/);
assert.match(workflowMigration, /CREATE OR REPLACE FUNCTION public\.finalize_crm_deal_approval/);
assert.match(workflowMigration, /UPDATE public\.crm_deals SET stage = 'NEGOTIATION', workflow_status = 'APPROVED'/);
assert.match(db, /rpc\('start_deal_approval'/);
assert.match(db, /rpc\('finalize_crm_deal_approval'/);

// Won/Lost handling stays present in both the client workflow and database API.
assert.match(workflowMigration, /CREATE OR REPLACE FUNCTION public\.change_crm_deal_stage/);
assert.match(workflowMigration, /CREATE OR REPLACE FUNCTION public\.mark_crm_deal_lost/);
assert.match(workflowMigration, /'NEGOTIATION', 'WON', 'LOST'/);

console.log('CRM Negotiation, approvals, Won/Lost, and historical-stage compatibility checks passed.');
