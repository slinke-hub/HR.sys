/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20261118130000_crm_previous_stage_transitions.sql'), 'utf8');
const app = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');

assert.match(migration, /OLD\.stage='QUALIFICATION' AND NEW\.stage IN \('LEAD','DISCUSSION'\)/);
assert.match(migration, /OLD\.stage='DISCUSSION' AND NEW\.stage='QUALIFICATION'/);
assert.match(migration, /OLD\.stage='NEGOTIATION' AND NEW\.stage='DISCUSSION'/);
assert.match(migration, /next_stage NOT IN \('LEAD','QUALIFICATION','DISCUSSION','NEGOTIATION'\)/);
assert.match(app, /oldStage === 'DISCUSSION' && newStage === 'NEGOTIATION'/);
assert.match(app, /oldStage === 'DISCUSSION' && newStage === 'QUALIFICATION'/);
console.log('CRM previous-stage transition checks passed.');
