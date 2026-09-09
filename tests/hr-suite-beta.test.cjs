const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const beta = fs.readFileSync(path.join(root, 'js', 'hr-suite-beta.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'hr-suite-beta.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260909090000_hr_suite_beta.sql'), 'utf8');

assert.match(html, /data-view="hr_suite_beta"/);
assert.match(html, /js\/hr-suite-beta\.js/);
assert.match(app, /case 'hr_suite_beta': content = await window\.renderHrSuiteBeta\(\)/);
assert.match(beta, /window\.canCurrentUserUseHrSuiteBeta/);
assert.match(beta, /RECRUITMENT.+ONBOARDING.+LEAVE.+PAYROLL.+COMPLIANCE.+OFFBOARDING/);
assert.match(beta, /Isolated testing workspace/);
assert.match(beta, /db\.fetchHrSuiteBetaItems\(\)/);
assert.match(beta, /db\.subscribeToHrSuiteBetaItems/);
assert.match(db, /async saveHrSuiteBetaItem/);
assert.match(db, /async updateHrSuiteBetaItemStatus/);
assert.match(css, /\.hr-beta-metrics/);
assert.match(css, /@media \(max-width:640px\)/);
assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.hr_suite_beta_items/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.can_manage_hr_suite_beta/);
assert.match(migration, /ENABLE ROW LEVEL SECURITY/);
assert.match(migration, /ALTER PUBLICATION supabase_realtime ADD TABLE/);
assert.doesNotMatch(beta, /mock|sample candidate|sample employee/i);

console.log('Isolated HR Suite Beta workflows are wired to live secured data.');
