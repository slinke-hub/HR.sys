const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const hotfix = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '20261001090000_fix_project_profile_directory_order.sql'),
  'utf8'
);
const frontend = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');

assert.match(hotfix, /CREATE OR REPLACE FUNCTION public\.list_accessible_project_profiles\(\)/);
assert.match(hotfix, /SELECT DISTINCT[\s\S]*profile\.full_name::TEXT[\s\S]*ORDER BY profile\.emp_index NULLS LAST, profile\.full_name::TEXT;/);
assert.doesNotMatch(hotfix, /ORDER BY profile\.emp_index NULLS LAST, profile\.full_name;/);
assert.match(hotfix, /public\.can_access_project\(project\.id, auth\.uid\(\)\)/);
assert.match(hotfix, /USING ERRCODE = '42501'/);
assert.match(frontend, /rpc\('list_accessible_project_profiles'\)/);

// Regression guard for PostgreSQL's DISTINCT rule: every ORDER BY expression
// must be represented by the corresponding selected expression.
const selectedFullName = hotfix.match(/profile\.full_name::TEXT/);
const orderedFullName = hotfix.match(/ORDER BY profile\.emp_index NULLS LAST, profile\.full_name::TEXT/);
assert.ok(selectedFullName && orderedFullName, 'ordered full_name must match the selected cast expression');

console.log('Project profile directory DISTINCT/ORDER BY regression guard passed.');
