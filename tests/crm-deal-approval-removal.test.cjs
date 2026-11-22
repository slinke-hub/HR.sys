/* eslint-env node */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261122100000_crm_remove_deal_approval_gate.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');

assert.match(migration, /OLD\.stage = 'DISCUSSION' AND NEW\.stage IN \('QUALIFICATION', 'NEGOTIATION'\)/,
  'The database transition trigger must allow Discussion to Negotiation without approval');
assert.doesNotMatch(migration, /Complete the registered Quote & Proposal task first|workflow_status\s*<>\s*'APPROVED'/,
  'The new stage transition migration must not retain CRM approval gates');
assert.match(migration, /public\.can_access_crm\(auth\.uid\(\)\)/,
  'CRM access verification must remain on the server');
assert.match(migration, /Deal assignment required/,
  'Only the deal creator or assigned employees may change its stage');
assert.match(migration, /has_function_privilege\('anon'.*'EXECUTE'\)/s,
  'Anonymous access must remain blocked');
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.change_crm_deal_stage\(uuid, text\) TO authenticated/,
  'Authenticated CRM users must retain the stage-change capability');
assert.match(app, /await window\.prepareCrmOrderModal\(String\(dealId\), newStage\)/,
  'The workflow Save action must open project order details after Negotiation is saved');
assert.match(app, /await window\.prepareCrmOrderModal\(dealId, newStage\)/,
  'The pipeline stage move must open project order details after Negotiation is saved');

console.log('CRM_DEAL_APPROVAL_REMOVAL=PASS');
