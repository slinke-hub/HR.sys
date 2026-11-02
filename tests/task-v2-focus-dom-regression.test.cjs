const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const helperStart = app.indexOf('function taskV2FilterMatches');
const filterStart = app.indexOf('window.filterTasksV2 = function', helperStart);
const filterEnd = app.indexOf('window.setTaskV2HealthFilter = function', filterStart);
assert.ok(helperStart >= 0 && filterStart > helperStart && filterEnd > filterStart, 'Focus filter source must remain extractable');
const filterSource = `${app.slice(helperStart, filterEnd)};`;

const tasks = [
    { id: 'focus-match', displayTitle: 'Critical release task', title: 'Critical release task', status: 'in_progress', priority: 'critical', created_by: 'creator-1', assignee_id: 'manager-1', due_date: '2026-11-03' },
    { id: 'focus-unrelated', displayTitle: 'Unrelated medium task', title: 'Unrelated medium task', status: 'todo', priority: 'medium', created_by: 'creator-2', assignee_id: '', due_date: '2026-12-20' },
    { id: 'focus-parent', displayTitle: 'Parent family task', title: 'Parent family task', status: 'todo', priority: 'medium', created_by: 'creator-1', assignee_id: 'manager-1', due_date: '2026-12-20' },
    { id: 'focus-child', displayTitle: 'Critical child task', title: 'Critical child task', parent_task_id: 'focus-parent', status: 'in_progress', priority: 'critical', created_by: 'creator-1', assignee_id: 'manager-1', due_date: '2026-11-03' }
];

const rows = tasks.map(task => `<article class="task-v2-row" data-task-id="${task.id}"></article>`).join('');
const html = `<!doctype html><html><head><style>.task-v2-row { display: grid !important; }</style></head><body>
<input id="taskV2Search"><select id="taskV2StatusFilter"><option value="all">all</option><option value="in_progress">in_progress</option><option value="completed">completed</option></select>
<select id="taskV2PriorityFilter"><option value="all">all</option><option value="critical">critical</option></select>
<select id="taskV2CreatorFilter"><option value="all">all</option><option value="creator-1">creator-1</option></select>
<select id="taskV2AssigneeFilter"><option value="all">all</option><option value="manager-1">manager-1</option></select>
<input id="taskV2DateFilter" type="date"><div data-task-health-count="waiting"></div><div data-task-health-count="active"></div>
<div data-task-health-count="due_this_week"></div><div data-task-health-count="overdue"></div><div data-task-health-total></div><div data-task-v2-visible-count></div>
<div id="task-v2-rows-container">${rows}</div><div id="tasks-view-board"><div class="task-stage-panel"><div class="task-column" id="col-todo"></div><div class="task-stage-count"></div></div></div>
</body></html>`;

(async () => {
    const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
    try {
        const page = await browser.newPage();
        await page.setContent(html);
        await page.evaluate((taskData, source) => {
            window.taskCache = Object.fromEntries(taskData.map(task => [task.id, task]));
            window.visibleTaskIds = taskData.map(task => task.id);
            window.projectsCache = [];
            window.taskListsCache = [];
            window.taskV2Mode = 'focus';
            window.taskV2HealthFilter = 'all';
            window.taskV2SelectedProject = 'all';
            window.eval(source);
        }, tasks, filterSource);

        const visibleIds = async () => page.$$eval('#task-v2-rows-container .task-v2-row', nodes => nodes.filter(node => !node.hidden && node.getAttribute('aria-hidden') !== 'true' && getComputedStyle(node).display !== 'none').map(node => node.dataset.taskId));
        const setControls = async controls => page.evaluate(next => {
            for (const [id, value] of Object.entries(next)) document.getElementById(id).value = value;
            window.filterTasksV2();
        }, controls);

        await setControls({ taskV2Search: 'critical' });
        assert.deepEqual(await visibleIds(), ['focus-match', 'focus-child']);

        await setControls({ taskV2Search: '', taskV2StatusFilter: 'in_progress' });
        assert.deepEqual(await visibleIds(), ['focus-match', 'focus-child']);

        await setControls({ taskV2StatusFilter: 'all', taskV2PriorityFilter: 'critical' });
        assert.deepEqual(await visibleIds(), ['focus-match', 'focus-child']);

        await setControls({ taskV2PriorityFilter: 'all', taskV2AssigneeFilter: 'manager-1' });
        assert.deepEqual(await visibleIds(), ['focus-match', 'focus-parent', 'focus-child']);

        await setControls({ taskV2Search: 'critical', taskV2PriorityFilter: 'critical', taskV2AssigneeFilter: 'manager-1' });
        assert.deepEqual(await visibleIds(), ['focus-match', 'focus-child']);

        await setControls({ taskV2Search: '', taskV2PriorityFilter: 'all', taskV2AssigneeFilter: 'all', taskV2DateFilter: '2026-11-03' });
        assert.deepEqual(await visibleIds(), ['focus-match', 'focus-child'], 'native date value filters by YYYY-MM-DD');

        await setControls({ taskV2DateFilter: '', taskV2StatusFilter: 'completed' });
        assert.deepEqual(await visibleIds(), [], 'a filter with no matching Focus task must hide every row');

        await setControls({ taskV2StatusFilter: 'all' });
        assert.deepEqual(await visibleIds(), ['focus-match', 'focus-parent', 'focus-child'], 'cleared filters preserve default Focus family grouping');

        await setControls({ taskV2StatusFilter: 'all', taskV2PriorityFilter: 'all', taskV2AssigneeFilter: 'all' });
        await page.evaluate(() => { window.taskV2Mode = 'list'; window.filterTasksV2(); });
        assert.deepEqual(await visibleIds(), ['focus-match', 'focus-unrelated', 'focus-parent', 'focus-child'], 'List mode keeps its direct filtered collection');
    } finally {
        await browser.close();
    }
    console.log('Task V2 Focus DOM visible-ID regression coverage passed.');
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
