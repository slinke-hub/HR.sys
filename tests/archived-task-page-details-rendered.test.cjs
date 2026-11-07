const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const start = app.indexOf('window.openTaskDetailsModal = async function (id) {');
const nextFunction = app.indexOf('window.handleTaskViewClick = function', start);
const end = app.lastIndexOf('};', nextFunction);
assert.ok(start >= 0 && nextFunction > start && end > start, 'Task details modal source must remain extractable.');
const modalSource = app.slice(start, end + 2);

const html = `<!doctype html><html><body>
<main id="archivedTasksPage"><h1>Archived Tasks</h1><button id="archivedTask">Archived sample</button></main>
<div id="editTaskModal"></div>
<div id="taskSidePanel" class="side-panel" hidden>
  <input id="detailsTaskId"><h2 id="detailsTaskTitle"></h2>
  <span id="detailsTaskAssignee"></span><span id="detailsTaskCreator"></span>
  <span id="detailsTaskStatus"></span><span id="detailsTaskPriority"></span>
  <span id="detailsTaskVisibility"></span><span id="detailsTaskStart"></span>
  <span id="detailsTaskDue"></span><span id="detailsTaskEnd"></span><span id="detailsTaskEstimate"></span>
  <div id="taskCommentsList"></div><div id="taskSubTasksList"></div>
  <button id="btnCreateSubTask"></button>
</div><div id="taskSidePanelOverlay" hidden></div></body></html>`;

(async () => {
  const scratchRoot = path.join(root, 'scratch');
  fs.mkdirSync(scratchRoot, { recursive: true });
  const userDataDir = fs.mkdtempSync(path.join(scratchRoot, 'archived-task-edge-'));
  let browser;
  try {
    browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'], userDataDir });
    const page = await browser.newPage();
    await page.setContent(html);
    await page.evaluate(source => {
      window.currentView = 'archived_tasks';
      window.currentUser = { id: 'synthetic-employee' };
      window.currentUserProfile = {};
      window.currentUserRole = 'EMPLOYEE';
      window.taskCache = {
        'synthetic-task': {
          id: 'synthetic-task', archived_at: '2026-11-01T00:00:00Z',
          status: 'completed', priority: 'medium', title: 'Synthetic archived task',
          assignee_id: 'synthetic-employee', assignee_ids: ['synthetic-employee']
        }
      };
      window.taskListsCache = [];
      window.taskAllUsersCache = [];
      window.canOpenTaskDetails = () => true;
      window.getLocalizedTaskTitle = task => task.title;
      window.formatEmployeeName = user => user?.id || '';
      window.taskDetailText = (english) => english;
      window.taskDetailValue = value => value || 'Not set';
      window.prepareTeamworkTaskDetail = async () => {};
      window.isMq20Profile = () => false;
      window.db = { fetchTaskComments: async () => [] };
      window.renderView = async view => { window.currentView = view; };
      window.eval(source);
    }, modalSource);

    await page.evaluate(() => window.openTaskDetailsModal('synthetic-task'));
    assert.equal(await page.evaluate(() => window.currentView), 'archived_tasks');
    assert.equal(await page.$eval('#taskSidePanel', panel => panel.classList.contains('active')), true);
    assert.equal(await page.$eval('#detailsTaskTitle', title => title.textContent), 'Synthetic archived task');
    assert.equal(await page.$eval('#archivedTasksPage h1', title => title.textContent), 'Archived Tasks');
  } finally {
    await browser?.close();
  }
  console.log('Archived task details render in place without leaving the archived tasks page.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
