/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'staging', 'deal_backend_services.sql'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const contract = fs.readFileSync(path.join(root, 'src', 'shared', 'domain-services.ts'), 'utf8');

for (const fn of [
  'get_crm_deal_secure', 'create_crm_deal_secure', 'update_crm_deal_secure',
  'assign_crm_deal_secure', 'list_crm_deal_activity_secure',
  'list_crm_deal_attachments_secure', 'register_crm_deal_attachment_secure',
  'delete_crm_deal_attachment_secure', 'log_crm_deal_activity_secure'
]) assert.match(migration, new RegExp(`FUNCTION public\\.${fn}`));
assert.match(migration, /REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public\.crm_deals/);
assert.match(migration, /REVOKE ALL ON TABLE public\.crm_deals, public\.crm_deal_activity, public\.crm_deal_attachments FROM anon/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.can_read_crm_deal_file/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.can_read_task_attachment_file/);
for (const rpc of [
  "rpc('get_crm_deal_secure'", "rpc('create_crm_deal_secure'", "rpc('update_crm_deal_secure'",
  "rpc('assign_crm_deal_secure'", "rpc('register_crm_deal_attachment_secure'",
  "rpc('log_crm_deal_activity_secure'", "rpc('delete_crm_deal_attachment_secure'"
]) assert.match(db, new RegExp(rpc.replace(/[()']/g, '\\$&')));
assert.doesNotMatch(db, /from\('crm_deals'\)\.insert/);
assert.doesNotMatch(db, /from\('crm_deals'\)\.update/);
assert.doesNotMatch(db, /from\('crm_deal_attachments'\)\.insert/);
assert.match(contract, /assignDeal\?/);
assert.match(contract, /fetchDealDetails\?/);
assert.match(contract, /removeDealAttachment\?/);
console.log('Deal authoritative backend façade checks passed.');
