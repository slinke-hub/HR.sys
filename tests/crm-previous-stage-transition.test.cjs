/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20261122100000_crm_remove_deal_approval_gate.sql'), 'utf8');
const app = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');

assert.match(migration, /OLD\.stage = 'QUALIFICATION' AND NEW\.stage IN \('LEAD', 'DISCUSSION'\)/);
assert.match(migration, /OLD\.stage = 'DISCUSSION' AND NEW\.stage IN \('QUALIFICATION', 'NEGOTIATION'\)/);
assert.match(migration, /OLD\.stage = 'NEGOTIATION' AND NEW\.stage = 'DISCUSSION'/);
assert.match(migration, /allowed_transition :=[\s\S]*d\.stage = 'DISCUSSION' AND next_stage IN \('QUALIFICATION', 'NEGOTIATION'\)/);
assert.doesNotMatch(migration, /Complete the registered Quote & Proposal task first/);
assert.match(app, /oldStage === 'DISCUSSION' && \['QUALIFICATION', 'NEGOTIATION'\]\.includes\(newStage\)/);
console.log('CRM stage transition checks passed.');
