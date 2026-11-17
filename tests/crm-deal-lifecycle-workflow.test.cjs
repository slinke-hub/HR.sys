/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'src', 'crm-dashboard.jsx'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

for (const mapping of [
  ["key: 'LEAD'", "dbStage: 'LEAD'"],
  ["key: 'CONTACT'", "dbStage: 'QUALIFICATION'"],
  ["key: 'PRESENTATION'", "dbStage: 'PITCH'"],
  ["key: 'DISCUSSION'", "dbStage: 'DISCUSSION'"],
  ["key: 'NEGOTIATION'", "dbStage: 'NEGOTIATION'"],
  ["key: 'WON'", "dbStage: 'WON'"],
  ["key: 'LOST'", "dbStage: 'LOST'"]
]) {
  assert.ok(source.includes(mapping[0]) && source.includes(mapping[1]), `Missing lifecycle mapping ${mapping.join(' / ')}`);
}

assert.match(source, /\['PITCH', 'PROPOSAL'\]\.includes\(value\).*'PRESENTATION'/s);
assert.match(source, /dbStage: 'PITCH'[^\n]*historical: true/);
assert.match(source, /if \(stage\.historical\) return/);
assert.match(source, /requiresDetails = \['DISCUSSION', 'WON', 'LOST'\]/);
assert.match(app, /newStage === 'PITCH' \|\| newStage === 'PROPOSAL'.*historical_stage/);
assert.match(app, /newStage === 'DISCUSSION'\) window\.openCrmPresentationRequest\('QUOTE_PROPOSAL'/);
assert.match(html, /id="dealQuoteProposalContinue"/);

assert.match(html, /id="dealLifecycleStepper"/);
assert.match(html, /id="dealProposalChecklist"/);
assert.match(html, /id="dealProjectSection"/);
assert.match(html, /id="closeDealProjectBtn"/);

assert.match(app, /const dealLifecycleStages = \[/);
assert.match(app, /categories\.has\('QUOTATION'\).*categories\.has\('PROPOSAL'\)/s);
assert.match(app, /db\.startCrmQuoteProposal\(dealId\)/);
assert.match(db, /rpc\('start_crm_quote_proposal'/);
assert.match(app, /newStage === 'LOST'/);
assert.match(app, /newStage === 'WON'/);
assert.match(app, /closeWonDealProjectFromWorkflow/);
assert.match(app, /categories\.has\('PHOTO'\)/);
assert.match(app, /typeof workflow\.project\.payment_ready === 'boolean'/);
assert.match(app, /paidAmount >= projectAmount/);

assert.match(db, /this\.fetchProjects\(\)/);
assert.match(db, /project: \(projects \|\| \[\]\)\.find\(project => String\(project\.deal_id\) === String\(dealId\)\)/);
assert.match(db, /async closeWonDealProject\(projectId\)/);
assert.match(db, /return this\.changeProjectStatus\(projectId, 'COMPLETED'\)/);

console.log('Simplified CRM lifecycle, historical display, won/lost, and project closing checks passed.');
