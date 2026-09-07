/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'src', 'crm-dashboard.jsx'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260907103000_crm_admin_approval_override.sql'), 'utf8');

assert.match(source, /const \[deals, setDeals\] = useState\(sourceDeals\)/);
assert.match(source, /useEffect\(\(\) => setDeals\(sourceDeals\), \[sourceDeals\]\)/);
assert.match(source, /onDealStageChange\(dealId, stage\.dbStage\)/);
assert.match(source, /if \(canMoveImmediately && !result\?\.success\) onDealStageChange\(dealId, oldStage\)/);
assert.doesNotMatch(source, /setTimeout\(\(\) => window\.renderView\?\.\('crm'\)/);

assert.match(app, /window\.refreshCrmDashboardInBackground = async function/);
assert.match(app, /void window\.refreshCrmDashboardInBackground\?\.\(\)/);
assert.match(app, /return \{ success: true, dealId, oldStage, newStage \}/);
assert.match(app, /data-approval-tab="crm"/);
assert.match(app, /handleCrmApprovalDecision/);
assert.match(app, /const canReject = isAdmin \|\| isDepartmentHead/);
assert.match(db, /async fetchPendingCrmApprovals\(\)/);

for (const role of ['ADMIN', 'OWNER', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN']) {
  assert.match(migration, new RegExp(`'${role}'`));
}
assert.match(migration, /v_step\.approver_id <> auth\.uid\(\) AND NOT v_actor_is_admin/);
assert.match(migration, /step_order < v_step\.step_order/);

console.log('CRM optimistic updates and administrator approval access tests passed.');
