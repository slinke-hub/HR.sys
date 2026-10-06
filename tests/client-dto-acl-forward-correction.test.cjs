/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migrationName = '20261005100000_revoke_direct_crm_client_dto_execute.sql';
const migrationPath = path.join(root, 'supabase', 'migrations', migrationName);
const sql = fs.readFileSync(migrationPath, 'utf8');
const phase1 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261002090000_project_operations_phase_1.sql'), 'utf8');
const reconciliation = fs.readFileSync(path.join(root, 'supabase', 'staging', 'client-reconciliation-readonly.sql'), 'utf8');
const s3Name = '20261005110000_security_hardening_s3.sql';

assert.match(sql, /^--[\s\S]*?\bBEGIN;[\s\S]*?\bCOMMIT;\s*$/);
assert.match(sql, /to_regprocedure\('public\.crm_client_dto\(public\.crm_clients\)'\)\s+IS\s+NULL/i);
assert.match(sql, /REVOKE\s+EXECUTE\s+ON\s+FUNCTION\s+public\.crm_client_dto\(public\.crm_clients\)\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated/i);
assert.match(sql, /NOTIFY\s+pgrst\s*,\s*'reload schema'/i);

// The migration may inspect and revoke only this exact helper signature.
const functionReferences = [...sql.matchAll(/(?:FUNCTION|to_regprocedure\()\s*'?\s*(public\.[a-z_][a-z_0-9]*)/gi)]
  .map((match) => match[1].toLowerCase());
assert.deepEqual([...new Set(functionReferences)], ['public.crm_client_dto']);
assert.doesNotMatch(sql, /\b(?:CREATE|ALTER|DROP)\s+(?:OR\s+REPLACE\s+)?FUNCTION\b/i);
assert.doesNotMatch(sql, /\b(?:GRANT|INSERT|UPDATE|DELETE|TRUNCATE|CREATE|ALTER|DROP)\b/i);
assert.doesNotMatch(sql, /get_crm_client_secure(?:_project_ops_base)?|list_crm_clients_secure|create_crm_client_secure|update_crm_client_secure|delete_crm_client_secure|crm_clients\s+(?:FROM|TO)/i);

// Forward ordering is unique and before S3; no Phase 1 façade definition is touched.
const version = migrationName.slice(0, 14);
assert.ok(version > '20261002090000' && version < s3Name.slice(0, 14));
assert.equal(fs.existsSync(path.join(root, 'supabase', 'migrations', s3Name)), true);
assert.match(phase1, /CREATE OR REPLACE FUNCTION public\.get_crm_client_secure\(/i);
assert.match(phase1, /get_crm_client_secure_project_ops_base/);
assert.doesNotMatch(sql, /get_crm_client_secure(?:_project_ops_base)?/i);

// The read-only staging reconciliation already expects the helper to be internal-only.
assert.match(reconciliation, /'public\.crm_client_dto\(public\.crm_clients\)'[^\n]*'internal'/);

console.log('Client DTO forward ACL correction scope checks passed.');
