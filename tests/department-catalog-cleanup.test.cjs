/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20261119120000_department_catalog_cleanup_and_designing.sql'), 'utf8');

assert.match(migration, /GROUP BY regexp_replace\(lower\(BTRIM\(name\)\)/);
assert.match(migration, /HAVING COUNT\(\*\) > 1/);
assert.match(migration, /UPDATE public\.%I SET department_id = \$1 WHERE department_id = \$2/);
assert.match(migration, /VALUES \('Designing', 'Design and creative production\.', TRUE\)/);
assert.match(migration, /name_ar = 'التصميم'/);
assert.match(migration, /NOTIFY pgrst/);

console.log('department-catalog-cleanup: PASS');
