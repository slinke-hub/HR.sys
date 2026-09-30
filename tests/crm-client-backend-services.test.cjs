/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const sql = fs.readFileSync(path.join(root, 'supabase', 'staging', 'client_backend_services.sql'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const shared = fs.readFileSync(path.join(root, 'src', 'shared', 'domain-services.ts'), 'utf8');
const bridge = fs.readFileSync(path.join(root, 'js', 'shared-services.js'), 'utf8');

for (const functionName of [
  'list_crm_clients_secure',
  'get_crm_client_secure',
  'create_crm_client_secure',
  'update_crm_client_secure',
  'delete_crm_client_secure'
]) {
  assert.match(sql, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${functionName}`));
  assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${functionName}`));
}

assert.match(sql, /crm_client_dto/);
assert.match(sql, /'deals'/);
assert.match(sql, /'projects'/);
assert.match(sql, /'tasks'/);
assert.match(sql, /'activity'/);
assert.match(sql, /can_view_business_financials/);
assert.match(sql, /REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public\.crm_clients FROM authenticated/);
assert.doesNotMatch(sql, /INSERT INTO public\.crm_clients\s*\([^)]*created_by/i);

assert.match(db, /rpc\('list_crm_clients_secure'/);
assert.match(db, /rpc\('get_crm_client_secure'/);
assert.match(db, /rpc\('create_crm_client_secure'/);
assert.match(db, /rpc\('update_crm_client_secure'/);
assert.match(db, /rpc\('delete_crm_client_secure'/);
assert.doesNotMatch(db, /from\('crm_clients'\)\.insert/);
assert.doesNotMatch(db, /from\('crm_clients'\)\.update/);
assert.doesNotMatch(db, /from\('crm_clients'\)\.delete/);
assert.match(shared, /fetchClientDetails/);
assert.match(shared, /search: \(search = ''\)/);
assert.match(bridge, /details: id => db\.fetchClientDetails/);

console.log('Client authoritative backend façade checks passed.');
