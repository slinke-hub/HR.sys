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
const visibilityMigration = read('supabase/migrations/20261024100000_crm_mq20_contact_task_visibility.sql');
const mq20HardeningMigration = read('supabase/migrations/20261026100000_mq20_task_service_authorization_hardening.sql');
const dependencyPrivacyMigration = read('supabase/migrations/20261027100000_task_dependency_visibility_hardening.sql');
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
assert.match(visibilityMigration, /CREATE OR REPLACE FUNCTION public\.can_view_own_crm_contact_task/);
assert.match(visibilityMigration, /p_user_id = auth\.uid\(\)/);
assert.match(visibilityMigration, /public\.is_mq20_profile\(p_user_id\)/);
assert.match(visibilityMigration, /public\.can_access_task\(p_task_id, p_user_id\)/);
assert.match(visibilityMigration, /generated\.kind = 'CONTACT_DISCUSSION'/);
assert.match(visibilityMigration, /generated\.deal_id = task\.crm_deal_id/);
assert.match(visibilityMigration, /task\.created_by = p_user_id[\s\S]*task\.assignee_id = p_user_id[\s\S]*p_user_id = ANY\(COALESCE\(task\.assignee_ids/);
assert.match(visibilityMigration, /REVOKE ALL ON FUNCTION public\.can_view_own_crm_contact_task\(uuid, uuid\) FROM PUBLIC, anon/);
assert.match(visibilityMigration, /CREATE POLICY mq20_only_ines_tasks_select ON public\.tasks AS RESTRICTIVE/);
assert.match(visibilityMigration, /OR public\.can_view_own_crm_contact_task\(id, auth\.uid\(\)\)/);
assert.doesNotMatch(visibilityMigration, /set_config\(|GRANT SELECT ON public\.tasks|GRANT .*task_lists/);
assert.doesNotMatch(visibilityMigration, /DROP POLICY IF EXISTS task_secure_access_select|CREATE POLICY task_secure_access_select/);
assert.match(mq20HardeningMigration, /p_user_id = auth\.uid\(\)/);
assert.match(mq20HardeningMigration, /OR public\.crm_is_own_generated_contact_task\(task\.id, auth\.uid\(\)\)/);
assert.match(mq20HardeningMigration, /generated\.kind = 'CONTACT_DISCUSSION'[\s\S]*task\.created_by = p_user_id[\s\S]*task\.assignee_id = p_user_id/);
assert.match(mq20HardeningMigration, /CREATE TRIGGER mq20_task_service_view_only[\s\S]*BEFORE INSERT OR UPDATE OR DELETE ON public\.tasks/);
assert.match(mq20HardeningMigration, /IF TG_TABLE_NAME = 'tasks' THEN[\s\S]*IF TG_OP = 'INSERT'[\s\S]*generated\.kind = 'CONTACT_DISCUSSION'/);
for (const table of ['task_comments','task_attachments','task_dependencies','task_waiting_history','task_blocker_history','task_lists']) {
  assert.match(mq20HardeningMigration, new RegExp(`'${table}'`));
}
assert.match(mq20HardeningMigration, /CREATE OR REPLACE FUNCTION public\.can_manage_task[\s\S]*NOT public\.is_mq20_profile\(auth\.uid\(\)\)/);
assert.match(mq20HardeningMigration, /CREATE OR REPLACE FUNCTION public\.can_execute_task[\s\S]*NOT public\.is_mq20_profile\(auth\.uid\(\)\)/);
assert.match(mq20HardeningMigration, /CREATE OR REPLACE FUNCTION public\.can_manage_task_attachments[\s\S]*NOT public\.is_mq20_profile\(auth\.uid\(\)\)/);
assert.doesNotMatch(mq20HardeningMigration, /DROP POLICY IF EXISTS task_secure_access_select|GRANT .*task_lists/);
assert.match(read('tests/fixtures/crm-release-1a-mq20-hardening-assertions.sql'), /client cannot spoof|cannot spoof/i);
assert.match(read('tests/fixtures/crm-release-1a-mq20-hardening-assertions.sql'), /cannot read another employee Contact task/);
assert.match(read('tests/fixtures/crm-release-1a-mq20-hardening-assertions.sql'), /generic task/);
assert.match(read('tests/crm-release-1a-postgres.test.cjs'), /20261026100000_mq20_task_service_authorization_hardening\.sql/);
assert.match(dependencyPrivacyMigration, /p_user_id = auth\.uid\(\)[\s\S]*can_access_task\(p_predecessor_task_id, p_user_id\)[\s\S]*can_access_task\(p_successor_task_id, p_user_id\)/);
assert.match(dependencyPrivacyMigration, /CREATE OR REPLACE FUNCTION public\.list_task_dependencies_secure[\s\S]*can_view_task_dependency\(predecessor\.id, successor\.id, auth\.uid\(\)\)/);
assert.match(dependencyPrivacyMigration, /CREATE POLICY task_dependencies_secure_select[\s\S]*can_view_task_dependency\(predecessor_task_id, successor_task_id, auth\.uid\(\)\)/);
assert.match(dependencyPrivacyMigration, /task_dependency_blocked_visible\(task\.id, auth\.uid\(\)\)/);
assert.match(dependencyPrivacyMigration, /task_activity_dependency_visible\(\s*activity\.task_id, activity\.action, activity\.metadata, auth\.uid\(\)\s*\)/);
assert.match(dependencyPrivacyMigration, /CREATE OR REPLACE FUNCTION public\.get_my_day[\s\S]*can_view_task_dependency\(predecessor\.id, task\.id, auth\.uid\(\)\)/);
assert.match(dependencyPrivacyMigration, /CREATE OR REPLACE FUNCTION public\.complete_task_productivity[\s\S]*visible_successors[\s\S]*can_access_task\(successor\.id, auth\.uid\(\)\)/);
assert.match(dependencyPrivacyMigration, /CREATE OR REPLACE FUNCTION public\.complete_and_hand_off_task[\s\S]*completion->'activated_successors'/);
assert.match(dependencyPrivacyMigration, /REVOKE ALL ON FUNCTION public\.task_dependency_blocked_visible\(uuid, uuid\) FROM PUBLIC, anon, authenticated/);
assert.match(dependencyPrivacyMigration, /DROP POLICY IF EXISTS task_activity_secure_select[\s\S]*CREATE POLICY task_activity_secure_select/);
assert.doesNotMatch(dependencyPrivacyMigration, /DELETE FROM public\.(?:task_dependencies|task_activity)|UPDATE public\.(?:task_dependencies|task_activity)/);
assert.match(read('tests/crm-release-1a-postgres.test.cjs'), /20261027100000_task_dependency_visibility_hardening\.sql/);
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
