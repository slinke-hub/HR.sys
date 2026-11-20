const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'css', 'ui-02-structural-layout.css'), 'utf8');

const helperStart = app.indexOf('function taskV2FilterMatches');
const helperEnd = app.indexOf('window.filterTasksV2 = function', helperStart);
assert.ok(helperStart >= 0 && helperEnd > helperStart, 'task V2 filter helper must remain independently testable');
const helper = new Function(`${app.slice(helperStart, helperEnd)}; return taskV2FilterMatches;`)();

const tasks = [
    { id: '1', displayTitle: 'Predecessor review', status: 'completed', priority: 'high', created_by: 'creator-1', assignee_id: 'manager-1', due_date: '2026-11-05' },
    { id: '2', displayTitle: 'Unrelated medium task', status: 'todo', priority: 'medium', created_by: 'creator-2', assignee_id: '', due_date: '2026-11-06' },
    { id: '3', displayTitle: 'High priority follow-up', status: 'in_progress', priority: 'high', created_by: 'creator-1', assignee_ids: ['manager-1'], due_date: '2026-11-07' }
];
const base = { projectsById: new Map(), taskListsById: new Map(), taskCache: Object.fromEntries(tasks.map(task => [task.id, task])), now: new Date('2026-11-02T12:00:00Z') };

assert.deepEqual(tasks.filter(task => helper(task, { ...base, query: 'predecessor' })).map(task => task.id), ['1']);
assert.deepEqual(tasks.filter(task => helper(task, { ...base, status: 'completed' })).map(task => task.id), ['1']);
assert.deepEqual(tasks.filter(task => helper(task, { ...base, priority: 'high' })).map(task => task.id), ['1', '3']);
assert.deepEqual(tasks.filter(task => helper(task, { ...base, assignee: 'manager-1' })).map(task => task.id), ['1', '3']);
assert.deepEqual(tasks.filter(task => helper(task, { ...base, creator: 'creator-2' })).map(task => task.id), ['2']);
assert.deepEqual(tasks.filter(task => helper(task, { ...base, dateFilter: '2026-11-06' })).map(task => task.id), ['2']);
assert.deepEqual(tasks.filter(task => helper(task, { ...base, query: 'high', priority: 'high', status: 'in_progress', assignee: 'manager-1' })).map(task => task.id), ['3']);
assert.deepEqual(tasks.filter(task => helper(task, { ...base, query: 'does-not-exist' })), []);
assert.deepEqual(tasks.filter(task => helper(task, base)).map(task => task.id), ['1', '2', '3']);

assert.match(app, /!hasExplicitTaskFilter/);
assert.match(app, /visibleRowIds/);
assert.match(app, /#task-v2-rows-container \.task-v2-row/);
assert.match(app, /style\.setProperty\('display', 'none', 'important'\)/);
assert.match(app, /setAttribute\('aria-hidden', String\(!matches\)\)/);
assert.match(app, /classList\.toggle\('task-v2-filtered-out', !matches\)/);
assert.match(app, /data-task-v2-visible-count/);
assert.match(css, /task-v2-filtered-out\[style\][\s\S]*display: none !important/);
assert.match(app, /id="btn-v2-board"[\s\S]*setTaskV2Mode\('board'\)/, 'Task Manager must expose the Pipeline view option');
assert.match(app, /\['focus', 'board', 'list'\]\.includes\(window\.taskV2Mode\)/, 'Pipeline mode must survive Task Manager rendering');
assert.match(app, /if \(!\['focus', 'board', 'list'\]\.includes\(mode\)\)/, 'Pipeline mode must be accepted by the view switcher');
assert.match(app, /boardContainer\.style\.display = mode === 'board' \? 'block' : 'none'/, 'Pipeline mode must show the board and hide the list');
assert.match(app, /task-v2-filter-label[^\n]*Find work[\s\S]*task-v2-search-input[\s\S]*id="taskV2Search"/, 'Find Work title is separate and above its input box');
assert.match(css, /task-v2-search-input\s*\{[\s\S]*border: 1px solid/);
assert.match(css, /task-v2-search:focus-within \.task-v2-search-input/);

console.log('Task V2 List/Focus/Pipeline filter regression coverage passed.');
