const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const crm = fs.readFileSync(path.join(root, 'src', 'crm-dashboard.jsx'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260915160000_business_financial_visibility.sql'), 'utf8');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.can_view_business_financials/);
assert.match(migration, /profile\.emp_index IN \(4, 5\)/);
assert.match(migration, /\(sales\|المبيعات\)/);
assert.match(migration, /\(marketing\|التسويق\)/);
assert.match(migration, /'MARKETING MANAGER'/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.list_crm_deals_secure/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.list_accessible_projects_secure/);
assert.match(migration, /REVOKE SELECT ON TABLE public\.crm_deals FROM authenticated/);
assert.match(migration, /column_name <> 'amount'/);
assert.match(migration, /column_name NOT IN \('project_amount', 'paid_amount', 'budget_amount', 'actual_cost'\)/);

assert.match(db, /rpc\('list_crm_deals_secure'/);
assert.match(db, /rpc\('list_accessible_projects_secure'/);
assert.match(db, /async canViewBusinessFinancials\(/);
assert.match(db, /rpc\('can_view_business_financials'/);
assert.doesNotMatch(db, /from\('crm_deals'\)\s*\.select\('\*, crm_clients\(\*\)'\)/);
assert.doesNotMatch(db, /from\('projects'\)\.select\('\*/);

assert.match(app, /ensureBusinessFinancialAccess/);
assert.match(app, /applyBusinessFinancialVisibility/);
assert.match(app, /\.\.\.\(canViewFinancials \? \[\[t\('crm_amount_sar'/);
assert.match(app, /canViewFinancials \? `<div><i data-lucide="wallet-cards"/);
assert.match(app, /canViewFinancials \? `<div><span>\$\{projectText\('budget'\)\}/);
assert.match(app, /if \(canCurrentUserViewBusinessFinancials\(\)\) data\.amount/);
assert.match(app, /if \(canCurrentUserViewBusinessFinancials\(\)\) \{\s*orderData\.project_amount/);

assert.match(crm, /canViewFinancials && Number\(deal\.amount/);
assert.match(crm, /canViewFinancials && <Metric icon=\{CircleDollarSign\}/);
assert.match(crm, /canViewFinancials && <div className="tw-min-w-0"><p[^\n]+\{text\.revenue\}/);
assert.match(html, /id="crmDealAmountGroup" data-business-financials/);
assert.match(html, /id="orderFinancialFields" data-business-financials/);

console.log('CRM and project financial visibility is restricted in the database responses and every active UI surface.');
