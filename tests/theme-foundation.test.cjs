const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const variables = read('css/variables.css');
const foundation = read('css/theme-foundation.css');
const components = read('css/components.css');
const app = read('js/app.js');
const html = read('index.html');

const semanticTokens = [
  '--bg-app', '--bg-surface', '--bg-surface-elevated', '--bg-subtle',
  '--text-primary', '--text-secondary', '--text-muted', '--border-default', '--border-subtle',
  '--brand-primary', '--brand-primary-soft', '--action-primary-bg', '--action-primary-hover',
  '--action-primary-text', '--success', '--warning', '--danger', '--info', '--focus-ring',
  '--shadow-sm', '--shadow-md', '--shadow-lg', '--hover-surface', '--selected-surface',
  '--disabled-surface', '--overlay-scrim', '--overlay-surface', '--input-bg', '--nav-bg',
];
const lightBlock = variables.match(/:root\s*\{([\s\S]*?)\n\}/)?.[1];
const darkBlock = variables.match(/\[data-theme="dark"\]\s*\{([\s\S]*?)\n\}/)?.[1];
assert.ok(lightBlock && darkBlock, 'Light and Dark semantic token blocks must exist');
for (const token of semanticTokens) {
  assert.match(lightBlock, new RegExp(`${token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:`), `Light theme is missing ${token}`);
  assert.match(darkBlock, new RegExp(`${token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:`), `Dark theme is missing ${token}`);
}

// UI-01 intentionally replaces the previous blue palette. Keep concrete palette
// checks alongside contrast checks so both design drift and unreadable states fail.
for (const [block, name, expected] of [
  [lightBlock, 'Light', {
    '--brand-primary': '#1B4C5F', '--brand-accent': '#168C86',
    '--bg-app': '#F6F8FA', '--bg-surface': '#FFFFFF',
    '--action-primary-bg': '#1B4C5F', '--nav-item-selected': '#E2EFEE',
  }],
  [darkBlock, 'Dark', {
    '--bg-app': '#14242E', '--action-primary-bg': '#286E80',
    '--action-primary-hover': '#327B8A', '--action-primary-text': '#FFFFFF',
    '--brand-primary': '#8FD3CF', '--focus-ring': '#76D3C9',
  }],
]) {
  for (const [token, expectedValue] of Object.entries(expected)) {
    assert.equal(tokenValue(block, token).toUpperCase(), expectedValue,
      name + ' ' + token + ' must match the approved UI-01 palette');
  }
}

function tokenValue(block, token) {
  assert.match(token, /^--[a-z-]+$/, 'Only semantic token names are accepted');
  const escaped = token;
  const value = block.match(new RegExp(escaped + '\\s*:\\s*([^;]+);'))?.[1].trim()
    || (block !== lightBlock ? lightBlock.match(new RegExp(escaped + '\\s*:\\s*([^;]+);'))?.[1].trim() : undefined);
  assert.ok(value, 'Missing semantic token ' + token);
  const alias = value.match(/^var\((--[\w-]+)\)$/);
  return alias ? tokenValue(block, alias[1]) : value;
}
function luminance(hex) {
  assert.match(hex, /^#[a-f\d]{6}$/i, 'Contrast checks require concrete RGB colors');
  const channels = hex.slice(1).match(/../g).map(channel => {
    const value = parseInt(channel, 16) / 255;
    return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
  });
  return channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
}
function contrast(a, b) {
  const values = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (values[0] + .05) / (values[1] + .05);
}
for (const [name, block] of [['Light', lightBlock], ['Dark', darkBlock]]) {
  for (const [foreground, background, minimum] of [
    ['--text-primary', '--bg-app', 4.5],
    ['--text-secondary', '--bg-surface', 4.5],
    ['--input-text', '--input-bg', 4.5],
    ['--input-placeholder', '--input-bg', 4.5],
    ['--input-border', '--input-bg', 3],
    ['--action-primary-text', '--action-primary-bg', 4.5],
    ['--action-primary-text', '--action-primary-hover', 4.5],
    ['--action-danger-text', '--action-danger-bg', 4.5],
    ['--selected-text', '--selected-surface', 4.5],
    ['--focus-ring', '--bg-surface', 3],
  ]) {
    assert.ok(contrast(tokenValue(block, foreground), tokenValue(block, background)) >= minimum,
      name + ' ' + foreground + ' against ' + background + ' must meet ' + minimum + ':1');
  }
  assert.notEqual(tokenValue(block, '--action-primary-bg'), tokenValue(block, '--brand-primary-soft'),
    'Primary actions must remain distinct from quiet selected surfaces');
}
assert.match(lightBlock, /--space-unit:\s*8px/, 'UI-01 uses the approved 8px rhythm');
assert.match(lightBlock, /--radius-md:\s*8px/, 'Shared controls use a consistent radius');
assert.match(lightBlock, /--radius-lg:\s*16px/, 'Elevated surfaces use a consistent radius');

for (const alias of ['--color-bg-subtle', '--color-text', '--color-text-muted', '--color-primary', '--color-bg-base']) {
  assert.match(variables, new RegExp(`${alias.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:\\s*var\\(`), `${alias} compatibility alias must resolve to a semantic token`);
}

const foundationHref = html.match(/<link[^>]+href="([^"]*theme-foundation\.css[^"]*)"/)?.[1];
assert.ok(foundationHref, 'HTML must load the shared theme foundation');
assert.ok(html.indexOf(foundationHref) > html.indexOf('css/crm-tailwind.css'), 'Theme foundation must load after existing component styles');
assert.match(foundation, /\.card\s*\{[\s\S]*?background:\s*var\(--bg-surface\)/, 'Shared card surface must use semantic tokens');
assert.match(foundation, /\.btn\.btn-primary[\s\S]*?background-color:\s*var\(--action-primary-bg\)/, 'Primary action must use its semantic action token');
assert.match(foundation, /\.btn\.btn-secondary[\s\S]*?background:\s*var\(--action-secondary-bg\)/, 'Secondary action foundation must exist');
assert.match(foundation, /\.btn\.btn-destructive[\s\S]*?background:\s*var\(--action-danger-bg\)/, 'Destructive action foundation must exist');
assert.match(foundation, /input[^\n]*textarea, select[\s\S]*?var\(--input-bg\)/, 'Shared form controls must use input tokens');
assert.match(foundation, /\.modal \.modal-content[\s\S]*?background:\s*var\(--overlay-surface\)/, 'Shared modal surface must use theme tokens');
assert.match(foundation, /:focus-visible[\s\S]*?outline:\s*3px solid var\(--focus-ring\)/, 'Global keyboard focus ring must be visible');
assert.match(foundation, /\.sidebar-nav \.nav-item\.active[\s\S]*?background:\s*var\(--nav-item-selected\)/, 'Selected navigation must use a soft semantic background');
assert.match(foundation, /\.mobile-navigation-item\.active/, 'Mobile navigation must share the selected state');
assert.match(foundation, /\.nav-item:not\(\.active\):not\(\[aria-current="page"\]\)[\s\S]*?var\(--nav-text-muted\)/, 'Inactive navigation must use the quieter text token');
assert.match(foundation, /\.btn\.btn-icon[\s\S]*?background:\s*var\(--action-secondary-bg\)/, 'Icon-only buttons must use the shared quiet treatment');
assert.match(foundation, /\.btn\.btn-icon[\s\S]*?background-image:\s*none !important/, 'Icon-only buttons must not inherit legacy gradients');
assert.match(foundation, /\.mobile-navigation-item::before[\s\S]*?display:\s*none !important/, 'More navigation tiles must not retain decorative color washes');
assert.match(foundation, /\.mobile-navigation-item\.active::before[\s\S]*?background:\s*var\(--nav-indicator\)/, 'Selected More item must retain a subtle logical-edge indicator');
assert.match(foundation, /\.mobile-navigation-item > :is\(i, svg\)[\s\S]*?background:\s*transparent !important/, 'More navigation icons must use the shared Lucide accent treatment');
assert.match(foundation, /\.mobile-navigation-item\.active > :is\(i, svg\)[\s\S]*?var\(--brand-primary\)/, 'Selected More item icon must use the brand color');
assert.match(foundation, /\.project-filter-bar input:focus[\s\S]*?var\(--input-border-focus\)/, 'Project filters must use semantic focus styling');
assert.match(foundation, /--icon-size-nav|var\(--icon-size-nav\)/, 'Navigation icon sizing token must be consumed');
assert.match(variables, /--icon-size-inline:\s*16px/, 'Inline/status icon size must be 16px');
assert.match(variables, /--icon-size-nav:\s*20px/, 'Navigation/action icon size must be 20px');
assert.match(variables, /--control-target-min:\s*40px/, 'Desktop controls must have a 40px minimum target');
assert.match(variables, /--control-target-touch:\s*44px/, 'Touch controls must have an approximately 44px target');
for (const icon of ['circle-check', 'circle-play', 'clock', 'octagon-alert', 'triangle-alert', 'calendar-clock', 'info', 'archive']) {
  assert.ok(foundation.includes(icon), `Status icon mapping must include Lucide ${icon}`);
}
assert.match(foundation, /color is never the sole cue/i, 'Status chips must pair semantic color with icon and visible label');

assert.match(app, /window\.toggleTheme\s*=\s*function/, 'Existing theme toggle must remain available');
assert.match(app, /muqam_hr_theme_\$\{currentUser\.id\}/, 'Existing per-user saved theme preference must remain available');
assert.match(html, /dir="rtl"/, 'RTL document support must remain enabled');
assert.match(foundation, /inset-inline-start/, 'Navigation indicator must use logical direction-aware positioning');
assert.match(components, /\.project-portfolio-card::before[^\n]*background:var\(--selected-indicator\)/, 'Project card top line must use a semantic brand token');
assert.doesNotMatch(components, /\.project-portfolio-card::before[^\n]*#[0-9a-fA-F]*8b5cf6/i, 'Project card decoration must not retain the legacy purple');
assert.match(components, /\.project-team-stack span[^\n]*background:var\(--action-primary-bg\)/, 'Project team initials must use the shared brand action family');
assert.match(app, /class="btn btn-primary" onclick="openProjectModal\(\)"/, 'New Project must use primary-action hierarchy');
assert.match(app, /class="btn btn-secondary" onclick="renderView\('project-command-center'\)"/, 'Command Center must remain secondary');
assert.match(app, /aria-label="\$\{escapeHTML\(projectText\('edit'\)\)\}"/, 'Project edit icon must expose a localized accessible name');
assert.match(html, /closeProjectEditor\('projectModal'\)[^>]*aria-label="Close" title="Close"/, 'Project modal close control must have an accessible label and tooltip');
assert.match(html, /header-search-trigger[^>]*aria-label="Search" title="Search"/, 'Shared search control must retain accessible label and tooltip');

console.log('Theme foundation static contract: PASS');
