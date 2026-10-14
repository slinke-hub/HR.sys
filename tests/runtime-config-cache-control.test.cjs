const assert = require('node:assert/strict');
const fs = require('node:fs');

const html = fs.readFileSync('index.html', 'utf8');
const app = fs.readFileSync('js/app.js', 'utf8');
const worker = fs.readFileSync('sw.js', 'utf8');
const vercel = fs.readFileSync('vercel.mjs', 'utf8');

assert.match(html, /runtime-config\.js/);
assert.match(html, /js\/db\.js\?v=2026101401-schedule-task-fixes/);
assert.match(html, /js\/app\.js\?v=2026101401-schedule-task-fixes/);
assert.match(app, /sw\.js\?v=2026101401-schedule-task-fixes/);
assert.match(worker, /const CACHE_NAME = 'muqam-hr-mobile-v259-schedule-task-fixes'/);
assert.doesNotMatch(worker.match(/const APP_SHELL = \[([\s\S]*?)\];/)?.[1] || '', /runtime-config\.js/);
assert.match(
  worker,
  /if \(url\.pathname === '\/runtime-config\.js'\)\s*\{\s*event\.respondWith\(fetch\(request, \{ cache: 'no-store' \}\)\);\s*return;\s*\}/,
);
assert.match(vercel, /src: '\/runtime-config\.js'[\s\S]*?Cache-Control': 'no-cache, no-store, must-revalidate'/);

console.log('Runtime config cache-control and worker-bypass checks passed.');
