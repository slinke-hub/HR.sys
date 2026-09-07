const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const appSource = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const dbSource = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const migrationSource = fs.readFileSync(
    path.join(root, 'supabase', 'migrations', '20260907123000_task_marketing_account_compatibility.sql'),
    'utf8'
);

test('marketing account labels submit the canonical database values', () => {
    assert.match(appSource, /<option value="Muqam\.party">Party<\/option>/);
    assert.match(appSource, /<option value="Muqamsa">Main<\/option>/);
    assert.doesNotMatch(appSource, /<option value="Party">Party<\/option>/);
    assert.doesNotMatch(appSource, /<option value="Main">Main<\/option>/);
    assert.match(dbSource, /if \(value === 'Party'\) return 'Muqam\.party';/);
    assert.match(dbSource, /if \(value === 'Main'\) return 'Muqamsa';/);
    assert.match(dbSource, /marketing_department: normalizeMarketingAccount\(marketingDepartment\)/);
    assert.match(dbSource, /normalizedUpdates\.marketing_department = normalizeMarketingAccount/);
});

test('database constraint remains compatible with clients cached during rollout', () => {
    for (const value of ['Muqamsa', 'Muqam.party', 'Coffee Corner', 'Main', 'Party']) {
        assert.ok(migrationSource.includes(`'${value}'`), `missing allowed account value: ${value}`);
    }
});
