const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(
    path.join(root, 'supabase', 'migrations', '20260908140000_add_sales_specialist_employee_titles.sql'),
    'utf8'
);

assert.match(migration, /LOWER\(BTRIM\(COALESCE\(department\.name, ''\)\)\) = 'sales'/);
assert.match(migration, /'Sales Specialist', 'أخصائي مبيعات', 'Mid-Level'/);
assert.match(migration, /'Sales Employee', 'موظف مبيعات', 'Entry-Level'/);
assert.match(migration, /is_active = TRUE/);
assert.match(migration, /NOTIFY pgrst, 'reload schema'/);

console.log('Sales Specialist and Sales Employee titles are assigned to the Sales department.');
