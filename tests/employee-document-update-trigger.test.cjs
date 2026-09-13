const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(
    path.join(root, 'supabase', 'migrations', '20260913120000_fix_employee_document_update_trigger.sql'),
    'utf8'
);

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.protect_employee_document_system_fields\(\)/);
assert.match(migration, /SECURITY DEFINER/);
assert.match(migration, /SET search_path = public, pg_temp/);
assert.match(migration, /'expiration_date'/);
assert.match(migration, /'owner_email'/);
assert.match(migration, /'owner_phone'/);
assert.doesNotMatch(migration, /NEW\.updated_at/);
assert.doesNotMatch(migration, /NEW\.is_verified/);
assert.doesNotMatch(migration, /NEW\.verified_by/);
assert.doesNotMatch(migration, /NEW\.verified_at/);

console.log('Employee document update trigger repair checks passed.');
