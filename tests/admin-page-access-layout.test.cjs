/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css/components.css'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const vercel = fs.readFileSync(path.join(root, 'vercel.json'), 'utf8');
const serviceWorker = fs.readFileSync(path.join(root, 'sw.js'), 'utf8');
const pageAccessSource = app.slice(
  app.indexOf('async function renderAdminPageAccess()'),
  app.indexOf('// Render User Management (Admin Only)')
);

assert.match(pageAccessSource, /page-access-workspace/);
assert.match(pageAccessSource, /page-access-metrics/);
assert.match(pageAccessSource, /page-access-bulk/);
assert.match(pageAccessSource, /pageAccessSearch/);
assert.match(pageAccessSource, /pageAccessStatusFilter/);
assert.match(pageAccessSource, /data-page-access-card/);
assert.match(pageAccessSource, /data-page-access-group/);
assert.match(pageAccessSource, /window\.filterAdminPageAccess = function/);
assert.match(pageAccessSource, /window\.handleBulkPageAccess = async function/);
assert.match(pageAccessSource, /currentPages\.filter\(page => !managedPages\.includes\(page\)\)/);
assert.match(pageAccessSource, /التحكم في صلاحيات الصفحات/);
assert.doesNotMatch(pageAccessSource, /<table class="data-table">/);

assert.match(css, /\.page-access-grid[\s\S]*repeat\(auto-fit/);
assert.match(css, /\.page-access-chip\.role/);
assert.match(css, /\.page-access-chip\.department/);
assert.match(css, /\.page-access-chip\.employee/);
assert.match(css, /@media \(max-width: 640px\)[\s\S]*\.page-access-toolbar \{ grid-template-columns: 1fr; \}/);
assert.match(db, /from\('user_permissions'\)[\s\S]*\.eq\('user_id', userId\)[\s\S]*\.maybeSingle\(\)/);
assert.match(html, /frame-src 'self' blob: https:\/\/vercel\.live/);
assert.match(vercel, /frame-src 'self' blob: https:\/\/vercel\.live/);
assert.match(serviceWorker, /muqam-hr-mobile-v228/);

console.log('Admin page access layout and interaction checks passed.');
