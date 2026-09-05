/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const appSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const dataSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'data.js'), 'utf8');
const workflowSource = fs.readFileSync(path.join(__dirname, '..', 'deal_workflow_migration.sql'), 'utf8');
const migrationSource = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260905130000_crm_pipeline_stages.sql'), 'utf8');
const expectedStages = ['LEAD', 'QUALIFICATION', 'PITCH', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST'];

const stageDeclaration = appSource.match(/const stages = \[([^\]]+)\];/);
assert.ok(stageDeclaration, 'CRM stage declaration was not found');
const actualStages = [...stageDeclaration[1].matchAll(/'([^']+)'/g)].map(match => match[1]);
assert.deepEqual(actualStages, expectedStages);

assert.doesNotMatch(appSource, /newStage === 'APPROVAL'/);
assert.doesNotMatch(workflowSource, /SET stage = 'APPROVAL'/);
assert.match(dataSource, /crm_qualification: "Qualification"/);
assert.match(dataSource, /crm_qualification: "التأهيل"/);
assert.match(dataSource, /crm_proposal: "Proposal"/);
assert.match(migrationSource, /CHECK \(stage IN \('LEAD', 'QUALIFICATION', 'PITCH', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST'\)\)/);
assert.doesNotMatch(migrationSource, /SET stage = 'APPROVAL'/);

console.log('CRM pipeline stage tests passed.');
