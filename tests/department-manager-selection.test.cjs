/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

assert.match(html, /id="departmentHead"/);
assert.match(app, /const employees = department\s+\?\s+\(window\.departmentProfilesCache \|\| \[\]\)\.filter\(profile => profile\.department_id === department\.id\)\s+:\s+\(window\.departmentProfilesCache \|\| \[\]\)\.filter\(profile => profile\.is_active !== false\)/);
assert.match(app, /head_id: document\.getElementById\('departmentHead'\)\.value \|\| null/);
assert.match(app, /db\.createDepartment\(data, \[\]\)/);

console.log('department-manager-selection: PASS');
