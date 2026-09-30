const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const layout = fs.readFileSync(path.join(root, 'css', 'layout.css'), 'utf8');

assert.match(db, /hr-runtime-indicator-full/);
assert.match(db, /hr-runtime-indicator-short/);
assert.match(css, /\.hr-runtime-indicator-full\s*\{\s*display:\s*none;/);
assert.match(css, /\.hr-runtime-indicator-short\s*\{\s*display:\s*inline;/);
assert.match(css, /\.employees-radar-live\s*\{\s*flex:\s*0 0 auto;\s*white-space:\s*nowrap;/);
assert.match(css, /\.my-day-task-actions\s*\{\s*width:\s*100%;\s*align-items:\s*stretch;/);
assert.match(css, /\.my-day-action\s*\{\s*min-height:\s*40px;/);
assert.match(css, /@media \(max-width: 430px\)/);
assert.match(css, /\.side-panel\.task-v2-detail\.teamwork-task-detail,\s*\n\s*\.side-panel\.teamwork-task-detail\s*\{[\s\S]*?width:\s*100vw !important;[\s\S]*?max-width:\s*100vw !important;/);
assert.match(css, /\.teamwork-task-detail \.side-panel-header\s*\{[\s\S]*?flex-wrap:\s*wrap;/);
assert.match(css, /\.teamwork-task-detail \.task-details-grid,\s*\n\s*\.teamwork-task-detail \.task-detail-data-grid\s*\{[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\);/);
assert.match(css, /\.teamwork-task-detail \.task-handoff-context\s*\{[\s\S]*?width:\s*100%;[\s\S]*?max-width:\s*100%;/);
assert.match(layout, /\.sidebar-nav\s*\{\s*display:\s*grid;/);
assert.match(layout, /\.sidebar-nav > #mobileMoreNav\s*\{\s*display:\s*flex !important;/);
assert.match(layout, /\.app-container > \.sidebar\s*\{\s*display:\s*flex !important;/);

console.log('Phase A+B mobile UX static checks passed.');
