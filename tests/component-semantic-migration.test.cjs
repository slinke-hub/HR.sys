const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const migration = read('css/component-semantic-migration.css');
const layout = read('css/layout.css');
const beta = read('css/hr-suite-beta.css');
const components = read('css/components.css');
const app = read('js/app.js');
const crmSource = read('src/crm-tailwind.css');
const crmDashboard = read('src/crm-dashboard.jsx');
const variables = read('css/variables.css');

const href = html.match(/<link[^>]+href="([^"]*component-semantic-migration\.css[^"]*)"/)?.[1];
assert.ok(href, 'Stage D semantic component migration stylesheet must be loaded');
assert.ok(html.indexOf(href) > html.indexOf('css/theme-foundation.css'), 'Component migration must load after the shared foundation');
assert.doesNotMatch(migration, /#[0-9a-f]{3,8}\b/i, 'Migration overrides must consume semantic tokens, not add hard-coded colors');

for (const token of [
  '--bg-surface', '--bg-surface-elevated', '--overlay-surface', '--text-primary',
  '--text-secondary', '--border-default', '--action-primary-bg', '--action-secondary-bg',
  '--action-danger-bg', '--brand-primary', '--success', '--warning', '--danger', '--info',
]) assert.ok(migration.includes(`var(${token})`), `Migration stylesheet must use ${token}`);

assert.match(migration, /\.card, \.project-card\)::before[\s\S]*?content:\s*none/i, 'Decorative card tops must be removed');
assert.match(migration, /\.btn-primary[\s\S]*?background-image:\s*none/i, 'Primary actions must not retain gradients');
assert.match(migration, /\.nav-beta-badge[\s\S]*?--brand-primary-soft/i, 'Beta navigation labels must use the quiet brand treatment');
assert.match(migration, /#editTaskDeleteBtn[\s\S]*?--action-danger-bg/i, 'Task deletion must retain destructive semantics without gradients');
assert.match(migration, /\.task-v2-status-completed[\s\S]*?--success-soft/i, 'Task completion status must use semantic success colors');
assert.match(migration, /\.task-v2-status-blocked[\s\S]*?--danger-soft/i, 'Blocked status must use semantic danger colors');
assert.match(migration, /:is\(\.modal \.modal-content[\s\S]*?--overlay-surface/i, 'Shared modal/dropdown surfaces must be themed');
assert.match(migration, /\.data-table th[\s\S]*?--bg-subtle/i, 'Table headers must use semantic surfaces');
assert.match(migration, /\.dashboard-admin-card[\s\S]*?--border-default/i, 'Dashboard admin surface must use the neutral component surface');
assert.match(migration, /\.notification-item\.unread[\s\S]*?--brand-primary/i, 'Unread notifications must use the semantic brand treatment');
assert.match(migration, /\.priority-ui-value\.priority-urgent[\s\S]*?--danger-soft/i, 'Urgent task priority must use semantic danger tokens');
assert.match(migration, /\.department-job-title-draft-row[\s\S]*?--bg-subtle/i, 'Admin draft rows must use a themed subtle surface');

assert.doesNotMatch(layout, /\.mobile-navigation-item:nth-child\(5n/i, 'Mobile More tiles must not be assigned unrelated hue by position');
assert.doesNotMatch(layout, /--item-accent(?:-end)?:\s*#[0-9a-f]/i, 'Mobile navigation must not retain per-item accent colors');
assert.doesNotMatch(beta, /#[0-9a-f]{3,8}\b/i, 'HR Suite Beta source must not retain literal UI colors');
assert.match(crmSource, /\.tw-bg-blue-600[\s\S]*?--action-primary-bg/, 'CRM primary utility must resolve through the shared action token');
assert.match(crmSource, /\.tw-bg-rose-50[\s\S]*?--danger-soft/, 'CRM danger surfaces must use semantic danger tokens');
assert.match(crmSource, /\.tw-bg-indigo-500[\s\S]*?--brand-primary/, 'CRM presentation-stage marker must use the shared brand token');
assert.match(crmSource, /\.tw-text-amber-700[\s\S]*?--warning/, 'CRM warning text must use the semantic warning token');
assert.match(crmSource, /\.tw-shadow-panel[\s\S]*?--shadow-sm/, 'CRM panel elevation must use shared semantic shadows');
assert.match(crmSource, /\.tw-bg-gradient-to-t[\s\S]*?background-image:\s*none/, 'CRM CTA gradients must be removed in favor of a solid action');
assert.match(crmSource, /\.crm-acquisition-chart-bar[\s\S]*?--chart-series-1[\s\S]*?--chart-series-2/, 'CRM acquisition chart must use chart-specific Light/Dark series tokens');
assert.match(crmSource, /\.tw-bg-slate-500[\s\S]*?--text-muted/, 'Neutral CRM pipeline stage must use the semantic muted token');
assert.match(crmSource, /\.tw-border-emerald-400[\s\S]*?--success/, 'CRM task status border must use semantic success');
assert.match(crmSource, /\.tw-ring-1[\s\S]*?--focus-ring/, 'CRM ring utilities must use the shared focus token');
assert.match(crmSource, /\.tw-shadow-float[\s\S]*?--shadow-md/, 'CRM hover elevation must use shared semantic shadow');
assert.match(crmSource, /\.tw-text-blue-400[\s\S]*?--brand-primary/, 'CRM icon hover must use semantic brand');
assert.doesNotMatch(crmDashboard, /tw-shadow-\[0_4px_16px_rgba/, 'CRM cards must not include arbitrary hard-coded shadow utilities');
assert.match(crmDashboard, /const colors = \['var\(--chart-series-1\)', 'var\(--chart-series-5\)', 'var\(--chart-series-3\)'\]/, 'CRM revenue data series must use chart-specific theme tokens');
assert.doesNotMatch(crmDashboard, /const colors = \['#[0-9a-f]{3,8}/i, 'CRM data-viz series must not hardcode Light-only colors');
assert.doesNotMatch(variables, /--gradient-(?:brand|warm|fresh):\s*linear-gradient/i, 'Legacy gradient aliases must not preserve rainbow decoration');
assert.doesNotMatch(components, /\.glass\s*\{/, 'Unused legacy glass surface treatment must be removed');
assert.doesNotMatch(components, /Color-rich experience layer|nth-of-type\(6n/i, 'Removed color-rich layer must not reintroduce rainbow module identity');
assert.match(app, /function applySemanticStatusIcons\(root = document\)/, 'Status icon enhancement must be shared by dynamically rendered modules');
assert.match(app, /function applyIconOnlyButtonNames\(root = document\)/, 'Icon-only controls must share one accessibility naming mechanism');
assert.match(app, /control\.setAttribute\('aria-label', label\)/, 'Icon-only controls must receive accessible names');
assert.match(app, /control\.setAttribute\('title', label\)/, 'Icon-only controls must receive localized tooltips');
assert.match(app, /applyIconOnlyButtonNames\(document\)/, 'Accessible icon labels must cover static shell and current view controls');
for (const icon of ['circle-check', 'circle-play', 'clock', 'octagon-alert', 'triangle-alert', 'calendar-clock', 'archive']) {
  assert.ok(app.includes(`icon: '${icon}'`), `Dynamic status enhancement must map to Lucide ${icon}`);
}
for (const state of ['critical', 'needs_attention', 'on_track']) {
  assert.ok(app.includes(state), `Dynamic status enhancement must recognize ${state}`);
}
assert.match(app, /applySemanticStatusIcons\(viewContainer\)/, 'Rendered views must receive status icon enhancement before Lucide rendering');
assert.match(app, /class="template-card-icon"/, 'Template cards must use semantic themed surfaces instead of decorative gradients');
assert.doesNotMatch(app, /gradient: 'linear-gradient\(135deg, #(?:667eea|f093fb|4facfe|43e97b|fa709a)/i, 'Legacy template color gradients must be removed');
assert.doesNotMatch(app, /🥇|🥈|🥉/, 'Performance status must use Lucide rather than medal emoji');
assert.match(app, /data-lucide="trophy"/, 'Target achievers must use the Lucide trophy icon');
assert.match(app, /announcement-icon-success/, 'Announcement icon must use a semantic success class');
assert.match(app, /dashboard-alert-warning/, 'Dashboard warning card must use a semantic warning class');
assert.match(app, /task-category-chip/, 'Task category chip must use the semantic brand surface');
assert.match(app, /request-row-highlight/, 'Request deep-link highlight must use a removable semantic class');
assert.match(app, /circle-check[\s\S]{0,120}circle-x/, 'Approval outcomes must use Lucide status icons');
assert.match(migration, /\.workflow-progress[\s\S]*?--bg-surface[\s\S]*?--border-default/, 'Request workflow surfaces must use shared semantic tokens');
assert.match(migration, /\.task-dependency-item\.is-blocking[\s\S]*?--warning-soft/, 'Dependency-blocked task state must remain semantically warning-colored');
assert.match(components, /--pipeline-purple:\s*var\(--brand-primary\)/, 'Task pipeline states must use semantic status/brand tokens rather than a separate purple identity');
assert.match(components, /--pipeline-red:\s*var\(--danger\)/, 'Task pipeline critical state must use semantic danger');

console.log('Semantic component migration static contract: PASS');
