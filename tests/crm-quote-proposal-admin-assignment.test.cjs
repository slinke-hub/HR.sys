/* eslint-env node */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migrationPath = path.join(__dirname, '..', 'supabase', 'migrations', '20261122110000_crm_quote_proposal_admin_assignment_bypass.sql');
const migration = fs.readFileSync(migrationPath, 'utf8');

assert.match(migration, /public\.can_access_crm\(auth\.uid\(\)\)/,
  'CRM access must remain mandatory');
assert.match(migration, /caller_is_admin boolean/,
  'The migration must identify trusted CRM administrator roles');
assert.match(migration, /IF NOT caller_is_admin\s+AND auth\.uid\(\) IS DISTINCT FROM d\.created_by[\s\S]*?Deal assignment required/,
  'Only administrators bypass the deal assignment restriction');
assert.match(migration, /IN \('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'\)/,
  'Administrator bypass must be restricted to explicit administrator roles');
assert.match(migration, /has_function_privilege\('anon',[\s\S]*?start_crm_quote_proposal[\s\S]*?'EXECUTE'\)/,
  'Anonymous execution must remain blocked');
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.start_crm_quote_proposal\(uuid\) TO authenticated, service_role/,
  'Authenticated CRM users must retain the RPC');

console.log('CRM_QUOTE_PROPOSAL_ADMIN_ASSIGNMENT=PASS');
