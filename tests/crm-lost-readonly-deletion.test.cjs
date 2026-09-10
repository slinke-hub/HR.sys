/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const app = read('js/app.js');
const db = read('js/db.js');
const source = read('src/crm-dashboard.jsx');
const css = read('css/components.css');
const migration = read('supabase/migrations/20260910100000_crm_lost_readonly_privileged_deletion.sql');

for (const id of ['crmLostDealSummaryModal', 'crmLostDealName', 'crmLostDealReason', 'crmLostDealDeleteButton']) {
  assert.match(html, new RegExp(`id="${id}"`));
}
assert.match(app, /const canCurrentUserDeleteCrmDeals = \(\) => isTaskAdmin\(\) \|\| isExecutiveAdminProfile\(\) \|\| isMarketingManagerProfile\(\)/);
assert.match(app, /window\.openLostDealSummaryModal = async function/);
assert.match(app, /canonicalDealLifecycleStage\(deal\.stage\) === 'LOST'/);
assert.match(app, /window\.deleteCrmDeal = function/);
assert.match(app, /window\.removeCrmDealLocally\?\.\(selectedDealId\)/);
assert.match(db, /async deleteDeal\(dealId\)/);
assert.match(db, /rpc\('delete_crm_deal', \{ p_deal_id: dealId \}\)/);

assert.match(source, /const isLost = normalizeStage\(deal\.stage\) === 'LOST'/);
assert.match(source, /if \(isLost\) window\.openLostDealSummaryModal/);
assert.match(source, /\{!isLost && <button aria-label=\{text\.editDeal\}/);
assert.match(source, /\{canDeleteDeals && <button aria-label=\{text\.deleteDeal\}/);
assert.match(source, /window\.removeCrmDealLocally = handleDealDelete/);
assert.match(css, /\.crm-lost-reason-summary-card/);

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.can_delete_crm_deal/);
assert.match(migration, /MARKETING MANAGER/);
assert.match(migration, /الرئيس التنفيذي\|المدير العام\|مدير/);
assert.match(migration, /DROP POLICY IF EXISTS "Users can delete deals"/);
assert.match(migration, /CREATE POLICY crm_privileged_deals_delete/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.protect_lost_crm_deal_edits/);
assert.match(migration, /OLD\.stage[\s\S]*= 'LOST'[\s\S]*NEW\.stage[\s\S]*= 'LOST'/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.delete_crm_deal/);

console.log('Lost deals are read-only and privileged CRM deletion is secured.');
