/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const app = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const pipelineStart = app.indexOf('const stageDefinitions = [', app.indexOf('const inProgress = tasks.filter'));
const pipelineEnd = app.indexOf('const boardHTML =', pipelineStart);
assert.notEqual(pipelineStart, -1, 'Pipeline stage definitions exist');
assert.notEqual(pipelineEnd, -1, 'Pipeline board follows its stage definitions');

const stageDefinitions = app.slice(pipelineStart, pipelineEnd);
assert.match(stageDefinitions, /status: 'in_progress'/);
assert.match(stageDefinitions, /tasks: inProgress/);
assert.doesNotMatch(stageDefinitions, /status: 'todo'|label: 'To Do'/);
assert.match(app, /const inProgress = tasks\.filter\(t => t\.status === 'in_progress'\)/);

console.log('task-pipeline-inprogress-only: PASS');
