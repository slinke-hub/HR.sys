/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260907100000_crm_approval_notifications.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.start_deal_approval/);
assert.match(migration, /INSERT INTO public\.notifications[\s\S]*?'crm_approval_requested'/);
assert.match(migration, /'step_id', v_first_step_id/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.decide_deal_approval/);
assert.match(migration, /ORDER BY step_order[\s\S]*?LIMIT 1/);
assert.match(migration, /v_next_step\.approver_id[\s\S]*?'crm_approval_requested'/);
assert.match(migration, /'crm_approval_rejected'/);
assert.match(migration, /'crm_approval_completed'/);
assert.match(migration, /action_url, metadata/);
assert.match(migration, /'\/?\?view=crm'/);
assert.match(migration, /Repair workflows that were started before notifications were added/);
assert.match(migration, /notification\.metadata ->> 'step_id' = step\.id::text/);

assert.match(app, /String\(notification\.event_type \|\| ''\)\.startsWith\('crm_'\)/);
assert.match(app, /notification\.metadata\?\.deal_id/);
assert.match(app, /await window\.openDealWorkflowModal\(String\(dealId\)\)/);

console.log('CRM approval notification workflow tests passed.');
