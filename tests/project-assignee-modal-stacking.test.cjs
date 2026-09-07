/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const css = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

assert.match(index, /id="(?:new|edit)ProjectAssignees"[^>]*multiple/);
assert.match(app, /overlay\.id = 'nativeMultiSelectModal'/);
assert.match(app, /document\.body\.appendChild\(overlay\)/);

const nestedPickerRule = css.match(/#nativeMultiSelectModal\.native-multi-select-modal\s*\{([^}]+)\}/);
assert.ok(nestedPickerRule, 'Missing stacking rule for the project assignee picker');
const pickerZIndex = Number(nestedPickerRule[1].match(/z-index:\s*(\d+)/)?.[1]);
const modalZIndex = Number(css.match(/\.modal\s*\{[\s\S]*?z-index:\s*(\d+)/)?.[1]);
assert.ok(pickerZIndex > modalZIndex, `Assignee picker z-index ${pickerZIndex} must exceed project modal z-index ${modalZIndex}`);
assert.match(nestedPickerRule[1], /!important/);

console.log('Project assignee modal stacking tests passed.');
