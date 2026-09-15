const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const data = fs.readFileSync(path.join(root, 'js', 'data.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

assert.match(app, /async function renderProfile\(\)/);
assert.match(app, /profile\.employee_id/);
assert.match(app, /profile\.emp_index/);
assert.match(app, /formatEmployeeId\(employeeNumberSource\)/);
assert.match(app, /id="profileCompanyEmployeeId"[^>]*readonly[^>]*aria-readonly="true"/);
assert.match(app, /t\('ui_employee_id'\)/);
assert.match(data, /ui_employee_id:\s*"Employee ID"/);
assert.match(data, /ui_employee_id:\s*"رقم الموظف"/);
assert.match(html, /js\/app\.js\?v=2026091512/);

console.log('Employees can see their read-only MQ company ID on their own profile.');
