/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '..', 'js', 'app.js'), 'utf8');
const start = source.indexOf('window.dropDeal = async (ev, newStage) => {');
const end = source.indexOf('\nwindow.closeLostReasonModal', start);
assert.ok(start >= 0 && end > start, 'CRM transition handler not found');

async function scenario(success) {
  const calls = [];
  const card = { getAttribute: name => name === 'data-stage' ? 'QUALIFICATION' : '' };
  const window = {
    moveDealCard: () => {}, refreshCrmDashboardInBackground: () => {},
    openCrmPresentationRequest: (kind, id) => calls.push(['modal',kind,id])
  };
  const document = { getElementById: id => id === 'deal-card-synthetic' ? card : null };
  const db = { updateDealStage: async (id,stage) => { calls.push(['server',id,stage]); return {success}; } };
  const context = { window, document, db, t: key => key, showToast: () => {} };
  vm.runInNewContext(source.slice(start,end), context);
  const event = { preventDefault() {}, dataTransfer: { getData: key => key === 'dealId' ? 'synthetic' : 'QUALIFICATION' } };
  const result = await window.dropDeal(event,'DISCUSSION');
  assert.equal(result.success,success);
  assert.deepEqual(calls[0],['server','synthetic','DISCUSSION']);
  assert.deepEqual(calls.slice(1),success ? [['modal','QUOTE_PROPOSAL','synthetic']] : []);
}

async function unsupportedStageScenario() {
  const calls = [];
  const card = { getAttribute: name => name === 'data-stage' ? 'QUALIFICATION' : '' };
  const window = { moveDealCard: () => calls.push(['restore']), refreshCrmDashboardInBackground: () => {} };
  const document = { getElementById: id => id === 'deal-card-synthetic' ? card : null };
  const db = { updateDealStage: async () => { calls.push(['server']); return { success: true }; } };
  const context = { window, document, db, t: key => key, currentLang: 'en', showToast: () => {} };
  vm.runInNewContext(source.slice(start,end), context);
  const event = { preventDefault() {}, dataTransfer: { getData: key => key === 'dealId' ? 'synthetic' : 'QUALIFICATION' } };
  const result = await window.dropDeal(event, 'LEAD');
  assert.equal(result.reason, 'unsupported_stage');
  assert.deepEqual(calls, [['restore']]);
}

async function negotiationWorkflowScenario() {
  const calls = [];
  const card = { getAttribute: name => name === 'data-stage' ? 'DISCUSSION' : '' };
  const window = {
    openDealWorkflowModal: id => calls.push(['workflow', id]),
    moveDealCard: () => calls.push(['restore']),
    refreshCrmDashboardInBackground: () => {}
  };
  const document = { getElementById: id => id === 'deal-card-synthetic' ? card : null };
  const db = { updateDealStage: async () => { calls.push(['server']); return { success: true }; } };
  const context = { window, document, db, currentLang: 'en', showToast: () => {} };
  vm.runInNewContext(source.slice(start, end), context);
  const event = { preventDefault() {}, dataTransfer: { getData: key => key === 'dealId' ? 'synthetic' : 'DISCUSSION' } };
  const result = await window.dropDeal(event, 'NEGOTIATION');
  assert.equal(result.reason, 'workflow_required');
  assert.deepEqual(calls, [['workflow', 'synthetic']]);
}

async function backwardTransitionScenario() {
  const calls = [];
  const card = { getAttribute: name => name === 'data-stage' ? 'DISCUSSION' : '' };
  const window = { moveDealCard: () => calls.push(['restore']), refreshCrmDashboardInBackground: () => {} };
  const document = { getElementById: id => id === 'deal-card-synthetic' ? card : null };
  const db = { updateDealStage: async () => { calls.push(['server']); return { success: false }; } };
  const context = { window, document, db, currentLang: 'en', showToast: () => {} };
  vm.runInNewContext(source.slice(start, end), context);
  const event = { preventDefault() {}, dataTransfer: { getData: key => key === 'dealId' ? 'synthetic' : 'DISCUSSION' } };
  const result = await window.dropDeal(event, 'QUALIFICATION');
  assert.equal(result.reason, 'invalid_stage_transition');
  assert.deepEqual(calls, [['restore']]);
}

(async () => {
  await scenario(true);
  await scenario(false);
  await unsupportedStageScenario();
  await negotiationWorkflowScenario();
  await backwardTransitionScenario();
  console.log('DISCUSSION_MODAL_SERVER_ORDER=PASS');
})().catch(error => { console.error(error); process.exitCode=1; });
