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
  ["key: 'DISCUSSION'", "dbStage: 'NEGOTIATION'"],
  ["key: 'WON'", "dbStage: 'WON'"],
  ["key: 'LOST'", "dbStage: 'LOST'"]
]) {
  assert.ok(source.includes(mapping[0]) && source.includes(mapping[1]), `Missing lifecycle mapping ${mapping.join(' / ')}`);
}

assert.match(source, /\['PITCH', 'PROPOSAL'\]\.includes\(value\).*'PRESENTATION'/s);
assert.match(source, /\['NEGOTIATION', 'WON'\]\.includes\(stage\.dbStage\)/);
assert.match(source, /requiresDetails = \['PITCH', 'WON', 'LOST'\]/);
assert.match(source, /approvalPending: 'Approval pending'/);
assert.match(source, /approvalRejected: 'Needs revision'/);

assert.match(html, /id="dealLifecycleStepper"/);
assert.match(html, /id="dealProposalChecklist"/);
assert.match(html, /id="dealProjectSection"/);
assert.match(html, /id="closeDealProjectBtn"/);

assert.match(app, /const dealLifecycleStages = \[/);
assert.match(app, /categories\.has\('QUOTATION'\).*categories\.has\('PROPOSAL'\)/s);
assert.match(app, /workflow\.approvals\.some\(step => step\.status === 'REJECTED'\)/);
assert.match(app, /approvals\.every\(step => String\(step\.status \|\| ''\)\.toUpperCase\(\) === 'APPROVED'\)/);
assert.match(app, /db\.updateDeal\(deal\.id, \{[\s\S]*stage: 'NEGOTIATION',[\s\S]*workflow_status: 'APPROVED'/);
assert.match(app, /newStage === 'LOST'/);
assert.match(app, /newStage === 'WON'/);
assert.match(app, /closeWonDealProjectFromWorkflow/);
assert.match(app, /categories\.has\('PHOTO'\)/);
assert.match(app, /Number\(project\.paid_amount \|\| 0\) >= Number\(project\.project_amount \|\| 0\)/);

assert.match(db, /from\('projects'\).*eq\('deal_id', dealId\)\.maybeSingle\(\)/s);
assert.match(db, /async closeWonDealProject\(projectId\)/);
assert.match(db, /update\(\{ project_status: 'Completed' \}\)/);

console.log('CRM lifecycle, approval, won/lost, and project closing workflow tests passed.');
