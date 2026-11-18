/* eslint-env node */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const app = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

assert.match(index, /id="dealWorkflowStageSave"[^>]*onclick="saveDealWorkflowStage\(\)"/,
    'Deal Workflow modal must expose a Save stage button');
assert.match(app, /window\.selectDealWorkflowStage = function \(stage\)/,
    'Deal Workflow stages must be selectable');
assert.match(app, /window\.saveDealWorkflowStage = async function \(\)/,
    'Deal Workflow stage save handler is missing');
assert.match(app, /oldStage === 'DISCUSSION' && newStage === 'NEGOTIATION'/,
    'Discussion to Negotiation must remain workflow-controlled');
assert.match(app, /oldStage === 'NEGOTIATION' && newStage === 'DISCUSSION'/,
    'Negotiation to Discussion must remain directly saveable');
assert.match(app, /context\.deal\.stage = newStage/,
    'Successful stage saves must update the active deal context');

console.log('CRM_WORKFLOW_STAGE_SAVE=PASS');
