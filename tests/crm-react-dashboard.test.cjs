/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'src', 'crm-dashboard.jsx'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'crm-tailwind.css'), 'utf8');
const cssSource = fs.readFileSync(path.join(root, 'src', 'crm-tailwind.css'), 'utf8');
const tailwindConfig = fs.readFileSync(path.join(root, 'tailwind.crm.config.cjs'), 'utf8');

for (const component of ['CrmDashboard', 'PipelineBoard', 'DealCard', 'TasksWidget', 'ActivityWidget', 'AssignmentsWidget', 'AnalyticsWidget']) {
  assert.match(source, new RegExp(`function ${component}\\(`), `Missing modular React component: ${component}`);
}

for (const stage of ['LEAD', 'CONTACT', 'PRESENTATION', 'DISCUSSION', 'WON', 'LOST']) {
  assert.match(source, new RegExp(`key: '${stage}'`), `Missing CRM stage: ${stage}`);
}

assert.match(source, /dir=\{lang === 'ar' \? 'rtl' : 'ltr'\}/);
assert.match(source, /draggable onDragStart=/);
assert.match(source, /id="crmDealPipelineBoard"/);
assert.match(source, /md:tw-grid-cols-2 2xl:tw-grid-cols-4/);
assert.doesNotMatch(source, /function Sidebar\(|function Header\(/, 'CRM must reuse the shared app shell');
assert.match(source, /className="page-header/);
assert.match(source, /className="search-container crm-dashboard-search/);
assert.match(source, /className="btn btn-primary/);
assert.match(source, /data-crm-new-deal/);
assert.match(source, /window\.showCRMDealModal\?\.\(\)/);
assert.match(source, /canOpenDetails/);
assert.match(source, /window\.openDealWorkflowModal\?\.\(String\(deal\.id\)\)/);
assert.match(source, /role=\{canOpenDetails \? 'button' : undefined\}/);
assert.match(source, /newDeal: 'New Deal'/);
assert.match(source, /newDeal: 'صفقة جديدة'/);
assert.match(source, /function EmployeeName\(\{ profile, lang \}\)/);
assert.match(source, /lang === 'ar'[\s\S]*profile\.display_name_ar[\s\S]*profile\.full_name/);
assert.match(source, /:\s*\[profile\.full_name_en, profile\.full_name, profile\.display_name, profile\.name, profile\.display_name_ar\]/);
assert.match(source, /<EmployeeName profile=\{profile\} lang=\{lang\} \/>/);
assert.doesNotMatch(source, /const initials =|profile\?\.initials \|\| initials\(name\)/);
assert.doesNotMatch(source, /SAMPLE_DEALS|__demo|demo-\d+|Al Noor Medical Group/);
assert.doesNotMatch(source, /const fallback = deals|const bars = \[38, 64/);
assert.match(source, /const sourceDeals = useMemo\(\(\) => \(payload\.deals \|\| \[\]\)\.map/);
assert.match(source, /const rows = activity\.slice\(0, 4\)/);
assert.match(source, /const industryRevenue = deals\.reduce/);
assert.match(app, /window\.MogamCrmDashboard\.mount\(root, crmPayload\)/);
assert.match(app, /window\.openCRMDealForClient = async/);
assert.match(app, /role: currentUserRole \|\| currentUserProfile\?\.role/);
assert.match(app, /dealWorkflowSummary/);
assert.match(index, /id="crmClientNewDealBtn"/);
assert.match(index, /id="dealWorkflowSummary"/);
assert.match(app, /Promise\.all\(\[[\s\S]*db\.fetchRecentCrmActivity\(8\)/);
assert.match(app, /document\.body\.classList\.remove\('crm-dashboard-active'\)/);
assert.doesNotMatch(app, /classList\.toggle\('crm-dashboard-active'/);
assert.match(db, /async fetchRecentCrmActivity\(limit = 8\)/);
assert.match(index, /css\/crm-tailwind\.css\?v=/);
assert.match(index, /js\/crm-dashboard\.bundle\.js\?v=/);
assert.match(tailwindConfig, /important:\s*true/, 'CRM utilities must override legacy !important theme rules');
assert.match(cssSource, /background-color: var\(--color-bg-surface\) !important/);
assert.match(cssSource, /color: var\(--color-text-primary\) !important/);
assert.match(cssSource, /\[data-theme="dark"\] #crm-react-root/);
assert.ok(css.length > 1000, 'Compiled Tailwind CRM stylesheet is unexpectedly small');

console.log('React CRM dashboard structure, RTL, pipeline, and SQL data mapping tests passed.');
