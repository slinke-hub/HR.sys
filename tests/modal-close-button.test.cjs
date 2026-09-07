const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const css = fs.readFileSync(path.join(__dirname, '..', 'css', 'components.css'), 'utf8');

assert.match(css, /Unified close control/);
assert.match(css, /\.close-modal::before,\s*\.close-modal::after/);
assert.match(css, /background-image: var\(--gradient-brand\) !important/);
assert.match(css, /transform: translateY\(-2px\) scale\(1\.04\)/);
assert.match(css, /:active \{\s*transform: translateY\(0\) scale\(\.96\)/);
assert.match(css, /:focus-visible \{\s*outline: 3px solid/);
assert.match(css, /@media \(hover: none\) and \(pointer: coarse\)[\s\S]*width: 44px/);

console.log('Modal close buttons use the shared app button effects.');
