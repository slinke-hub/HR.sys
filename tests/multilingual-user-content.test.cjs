/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const start = app.indexOf('const MOJIBAKE_REPLACEMENTS');
const end = app.indexOf('// XSS Protection Utility', start);
assert.ok(start >= 0 && end > start, 'Shared text encoding repair helper must exist.');

const context = { window: {} };
vm.createContext(context);
vm.runInContext(`${app.slice(start, end)};globalThis.repair = repairTextEncoding;`, context);

const arabic = 'طلب إجازة قصيرة';
const legacyArabic = Buffer.from(arabic, 'utf8').toString('latin1');
assert.equal(context.repair(arabic), arabic, 'Valid Arabic content must remain unchanged.');
assert.equal(context.repair(legacyArabic), arabic, 'Legacy UTF-8 mojibake must be restored.');
assert.equal(context.repair('Short Leave Â· 2026-09-15 â€“ 2026-09-15'), 'Short Leave · 2026-09-15 – 2026-09-15');
assert.match(app, /return repairTextEncoding\(str\)/);
assert.match(app, /return repairTextEncoding\(preferred\)/);
assert.match(app, /item\.leave_type[\s\S]*` · \$\{item\.start_date\} –/);

console.log('Arabic user-entered content remains readable in English and Arabic interface modes.');
