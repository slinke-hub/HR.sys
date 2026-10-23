const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const app = read('js/app.js');
const react = read('src/crm-dashboard.jsx');
const db = read('js/db.js');
const migration = read('supabase/migrations/20261022100000_crm_release_1a.sql');
assert.match(react, /key: 'CONTACT', dbStage: 'QUALIFICATION'/);
assert.doesNotMatch(react, /key: 'DISCUSSION'/);
assert.doesNotMatch(app, /stage: 'NEGOTIATION', label:/);
assert.doesNotMatch(app, /reason: 'approval_required'/);
assert.doesNotMatch(db, /rpc\('(?:start_deal_approval|decide_deal_approval|decide_crm_design_task_approval|finalize_crm_deal_approval)'/);
assert.match(migration, /PRIMARY KEY \(deal_id, kind\)/);
assert.match(migration, /task_id uuid NOT NULL UNIQUE REFERENCES public.tasks/);
assert.match(migration, /CURRENT_TIMESTAMP AT TIME ZONE 'Asia\/Riyadh'/);
assert.match(migration, /FOR UPDATE/);
assert.doesNotMatch(migration, /DELETE FROM public\.crm_(?:deal|design_task)_approval_steps|UPDATE public\.crm_(?:deal|design_task)_approval_steps/);
assert.doesNotMatch(migration, /set_config\(/);
assert.doesNotMatch(migration, /workflow_status <> 'APPROVED'/);
assert.match(migration, /Financial access denied/);
assert.match(migration, /v_deal\.proposal_sent_at IS NULL[\s\S]*Submit the Presentation before opening a project/);
assert.match(migration, /DROP TRIGGER IF EXISTS crm_deals_enforce_workflow_transition ON public\.crm_deals;[\s\S]*?CREATE TRIGGER crm_deal_workflow_transition\s+BEFORE INSERT OR UPDATE OF stage, workflow_status, lost_reason ON public\.crm_deals\s+FOR EACH ROW EXECUTE FUNCTION public\.enforce_deal_workflow_transition\(\)/i);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.can_add_task_to_list\(uuid, uuid\) FROM PUBLIC, anon;[\s\S]*?GRANT EXECUTE ON FUNCTION public\.can_add_task_to_list\(uuid, uuid\) TO authenticated;/i);
assert.doesNotMatch(read('tests/crm-release-1a-postgres.test.cjs'), /CREATE TRIGGER crm_deals?_enforce_workflow_transition/);
assert.match(migration, /Event End Date cannot be before the Event Date/);
assert.match(migration, /Every added equipment item needs an item name and quantity/);
const generatedInsert = migration.match(/INSERT INTO public\.tasks\([\s\S]*?\);/)[0];
assert.doesNotMatch(generatedInsert, /created_at/);
assert.match(read('index.html'), /crm-dashboard\.bundle\.js\?v=2026102201/);
assert.match(read('sw.js'), /muqam-hr-mobile-v256/);
const drop = app.slice(app.indexOf('window.dropDeal = async'), app.indexOf('window.closeLostReasonModal'));
const calls = [];
const context = {
  window: { hrDomainServices: { deals: { changeStage: async (...args) => { calls.push(['stage',...args]); return {success:true}; } } },
    moveDealCard: () => {}, refreshCrmDashboardInBackground: () => {},
    prepareCrmOrderModal: async id => calls.push(['order',id]),
    openCrmPresentationChoiceModal: id => calls.push(['presentation',id]) },
  document: { getElementById: () => null }, showToast: () => {}, t: key => key,
  db: { logDealActivity: () => { throw Error('Stage RPC must own atomic audit logging'); } }
};
vm.createContext(context); vm.runInContext(drop, context);
const event = { preventDefault() {}, dataTransfer: { getData: key => key==='dealId'?'deal-1':'LEAD' } };
(async () => {
  assert.equal((await context.window.dropDeal(event,'QUALIFICATION')).success,true);
  assert.deepEqual(calls.pop(),['stage','deal-1','QUALIFICATION']);
  assert.equal((await context.window.dropDeal(event,'WON')).reason,'won_details_required');
  assert.deepEqual(calls.pop(),['order','deal-1']);
  assert.equal((await context.window.dropDeal(event,'PITCH')).reason,'presentation_type_required');
  assert.deepEqual(calls.pop(),['presentation','deal-1']);
  assert.equal((await context.window.dropDeal(event,'NEGOTIATION')).reason,'retired_stage');
  assert.equal(calls.length,0);
  console.log('Release 1A client behavior and static migration/security checks passed. SQL was inspected, not executed by this test.');
})().catch(error => { console.error(error); process.exitCode=1; });
