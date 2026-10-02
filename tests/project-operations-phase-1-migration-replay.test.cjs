const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261002090000_project_operations_phase_1.sql'), 'utf8');
const createBase = migration.indexOf('CREATE OR REPLACE FUNCTION public.project_operational_snapshot');
const facadeGuard = migration.indexOf('DO $project_ops_client_facade$');
const facadeWrapper = migration.indexOf('CREATE OR REPLACE FUNCTION public.get_crm_client_secure(');

assert.equal((migration.match(/^BEGIN;$/gm) || []).length, 1, 'migration has one transaction start');
assert.equal((migration.match(/^COMMIT;$/gm) || []).length, 1, 'migration has one transaction commit');
assert.ok(createBase >= 0 && facadeGuard > createBase && facadeWrapper > facadeGuard, 'function changes are within the transaction');
assert.match(migration.slice(facadeGuard, facadeWrapper), /to_regprocedure\('public\.get_crm_client_secure_project_ops_base\(uuid\)'\) IS NULL/);
assert.match(migration.slice(facadeGuard, facadeWrapper), /to_regprocedure\('public\.get_crm_client_secure\(uuid\)'\) IS NULL/);
assert.match(migration.slice(facadeGuard, facadeWrapper), /EXECUTE 'ALTER FUNCTION public\.get_crm_client_secure\(uuid\) RENAME TO get_crm_client_secure_project_ops_base'/);
assert.match(migration.slice(facadeGuard, facadeWrapper), /END;\s*\$project_ops_client_facade\$;/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.get_crm_client_secure\(p_client_id uuid\)/);
assert.doesNotMatch(migration, /DROP FUNCTION|DROP TABLE|DROP COLUMN|TRUNCATE|DELETE FROM/i);

console.log('Project Operations Phase 1 migration replay guards passed (static validation; migration not executed).');
