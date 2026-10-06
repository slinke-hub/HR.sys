const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migrationPath = path.join(
  root,
  'supabase',
  'migrations',
  '20261001100000_revoke_project_profile_directory_public_execute.sql'
);
const migration = fs.readFileSync(migrationPath, 'utf8');
const historicalOrdering = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '20261001090000_fix_project_profile_directory_order.sql'),
  'utf8'
);
const phaseOne = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '20261002090000_project_operations_phase_1.sql'),
  'utf8'
);

assert.match(migration, /to_regprocedure\('public\.list_accessible_project_profiles\(\)'\)\s+IS NULL/i);
assert.match(
  migration,
  /REVOKE\s+EXECUTE\s+ON\s+FUNCTION\s+public\.list_accessible_project_profiles\(\)\s+FROM\s+PUBLIC\s*,\s*anon\s*;/i
);
assert.match(
  migration,
  /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.list_accessible_project_profiles\(\)\s+TO\s+authenticated\s*;/i
);
assert.match(migration, /NOTIFY\s+pgrst\s*,\s*'reload schema'\s*;/i);
assert.doesNotMatch(migration, /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION|ALTER\s+FUNCTION|DROP\s+FUNCTION/i);
assert.doesNotMatch(migration, /\b(?:INSERT|UPDATE|DELETE|TRUNCATE|ALTER\s+TABLE|DROP\s+TABLE|CREATE\s+POLICY|DROP\s+POLICY)\b/i);

// Only the specified profile-directory function may appear in privilege DDL.
const privilegeStatements = migration.match(/\b(?:GRANT|REVOKE)\b[\s\S]*?;/gi) || [];
assert.equal(privilegeStatements.length, 2, 'migration must contain exactly one REVOKE and one GRANT');
for (const statement of privilegeStatements) {
  assert.match(statement, /ON\s+FUNCTION\s+public\.list_accessible_project_profiles\(\)/i);
}

// This is a forward ACL-only correction: historical ordering and Phase 1 façade
// definitions remain separate and are not rewritten by this migration.
assert.match(historicalOrdering, /CREATE OR REPLACE FUNCTION public\.list_accessible_project_profiles\(\)/);
assert.match(phaseOne, /get_crm_client_secure_project_ops_base|project_operational_snapshot/i);
assert.doesNotMatch(migration, /get_crm_client_secure|project_operational_snapshot|project_completion_readiness/i);

console.log('Project profile directory ACL correction scope guards passed (static only; migration not executed).');
