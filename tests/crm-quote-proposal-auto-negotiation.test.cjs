/* eslint-env node */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261122130000_crm_quote_proposal_completion_advances_negotiation.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');

assert.match(migration, /crm_quote_proposal_completion_advances_deal[\s\S]*?AFTER UPDATE OF status ON public\.tasks/,
  'Completing the Quote & Proposal task must trigger the deal transition');
assert.match(migration, /mapping\.kind = 'QUOTE_PROPOSAL'[\s\S]*?task\.crm_workflow_kind = 'QUOTE_PROPOSAL'/,
  'Only the registered CRM task may advance its linked deal');
assert.match(migration, /submission_links\), 0\) > 0/,
  'At least one completed design deliverable is required');
assert.match(migration, /source_file\.category = 'QUOTATION'[\s\S]*?source_file\.category = 'PROPOSAL'/,
  'The original quote and described proposal image remain required');
assert.match(migration, /attachment\.is_archived = false[\s\S]*?attachment\.file_type = 'application\/pdf'/,
  'Every submitted deliverable must be a current registered PDF or image');
assert.match(migration, /SET stage = 'NEGOTIATION'[\s\S]*?INSERT INTO public\.crm_deal_activity/,
  'The database must advance the stage and record its activity atomically');
assert.match(migration, /Complete all required Quote & Proposal fields and files before Negotiation/,
  'Manual stage changes must remain blocked until completion requirements pass');
assert.match(migration, /has_function_privilege\('authenticated', 'hrsys_private\.crm_quote_proposal_submission_ready\(uuid\)', 'EXECUTE'\)/,
  'The private readiness helper must not be callable by authenticated users');
assert.match(app, /task\?\.crm_workflow_kind === 'QUOTE_PROPOSAL'[\s\S]*?refreshCrmDashboardInBackground/,
  'The CRM board should refresh after task completion');

console.log('CRM_QUOTE_PROPOSAL_AUTO_NEGOTIATION=PASS');
