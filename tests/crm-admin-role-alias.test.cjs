/* eslint-env node */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const app = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20261118150000_crm_admin_role_alias.sql'), 'utf8');

assert.match(app, /'SYSTEM ADMINISTRATOR'/, 'Client admin guard must recognize System Administrator');
assert.match(migration, /'SYSTEM ADMINISTRATOR'/, 'Database delete guard must recognize System Administrator');
assert.match(migration, /profile\.is_active IS DISTINCT FROM false/, 'Delete guard must require an active profile');
assert.match(migration, /REVOKE ALL ON FUNCTION public\.can_delete_crm_deal\(uuid\) FROM PUBLIC, anon/, 'Delete guard must remain non-public');
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.can_delete_crm_deal\(uuid\) TO authenticated/, 'Delete guard must remain authenticated-only');

console.log('CRM_ADMIN_ROLE_ALIAS=PASS');
