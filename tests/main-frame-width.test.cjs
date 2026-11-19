/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const css = fs.readFileSync(path.join(root, 'css', 'ui-02-structural-layout.css'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

assert.match(css, /@media \(min-width: 768px\)[\s\S]*\.main-content\s*\{[\s\S]*padding-inline: clamp\(\.75rem, 1\.2vw, 1\.25rem\)/);
assert.match(css, /\.main-content > #viewContainer\s*\{[\s\S]*padding-inline: clamp\(\.75rem, 1\.2vw, 1\.25rem\)/);
assert.match(html, /ui-02-structural-layout\.css\?v=2026111901/);

console.log('main-frame-width: PASS');
