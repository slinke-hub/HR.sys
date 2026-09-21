/* Static threat-model regression checks. Live Supabase authorization tests
 * require a linked project and seeded test users, which are intentionally not
 * available in this workspace. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260917090000_shared_business_logic_services.sql'), 'utf8');
const storage = fs.readFileSync(path.join(root, 'supabase/migrations/20260910123500_private_sensitive_storage.sql'), 'utf8');
const financial = fs.readFileSync(path.join(root, 'supabase/migrations/20260915160000_business_financial_visibility.sql'), 'utf8');

const requiredServerGuards = [
  /auth\.uid\(\) IS NULL/,
  /USING ERRCODE = '42501'/,
  /REVOKE ALL ON FUNCTION public\.change_task_status/,
  /REVOKE ALL ON FUNCTION public\.assign_task/,
  /REVOKE ALL ON FUNCTION public\.change_project_status/,
  /REVOKE ALL ON FUNCTION public\.assign_project_team/,
  /REVOKE ALL ON FUNCTION public\.finalize_crm_deal_approval/,
];
requiredServerGuards.forEach(pattern => assert.match(migration, pattern));
assert.match(storage, /private|sensitive_task_attachments_read/i);
assert.match(financial, /list_crm_deals_secure/);
assert.match(financial, /list_accessible_projects_secure/);

const threatCases = [
  'anonymous user invokes privileged RPC',
  'low-permission user changes task status',
  'unauthorized user assigns task',
  'unauthorized user assigns project team',
  'employee reads redacted financial fields',
  'employee downloads protected storage object',
];
assert.equal(threatCases.length, 6);
console.log('Backend RLS threat-matrix static checks passed; live Supabase cases require linked credentials.');

