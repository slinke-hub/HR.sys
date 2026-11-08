const assert = require('node:assert/strict');
const fs = require('node:fs');

const app = fs.readFileSync('js/app.js', 'utf8');
const modalStart = app.indexOf('window.openTaskDetailsModal = async function (id) {');
const modalEnd = app.indexOf('window.handleTaskViewClick = function', modalStart);
const modal = app.slice(modalStart, modalEnd);
const archivedRenderer = app.slice(app.indexOf('async function renderArchivedTasks()'), app.indexOf('window.filterArchivedTasks = function'));
const detailsTab = app.slice(app.indexOf('window.setTaskDetailInfoTab = function'), app.indexOf('window.setTaskActivityTab = async function'));
const subtaskComposer = app.slice(app.indexOf('window.openInlineSubtaskComposer = function'), app.indexOf('window.addInlineSubtaskRow = function'));
const subtaskSubmit = app.slice(app.indexOf('window.submitInlineSubtask = async function'), app.indexOf('window.requestTaskCompletionNote = function'));
const viewRendererStart = app.indexOf('const isTaskDetailsView =', app.indexOf('window.renderView = async function'));
const viewRenderer = app.slice(viewRendererStart, app.indexOf("if (viewId !== 'login')", viewRendererStart));

assert.ok(modalStart >= 0 && modalEnd > modalStart, 'Task detail opener must remain discoverable.');
assert.match(modal, /const preserveArchivedTaskView = currentView === 'archived_tasks' && !!task\.archived_at/,
  'Opening an archived task from the archive must preserve its current view.');
assert.match(modal, /if \(!preserveArchivedTaskView && !\['tasks', 'tasks_v2'\]\.includes\(currentView\)\)\s*\{\s*await renderView\('tasks'\);/,
  'Only non-archive contexts should fall back to Task Manager.');
assert.match(viewRenderer, /const isTaskDetailsView = viewId === 'tasks' \|\| viewId === 'archived_tasks'/,
  'The detail panel must remain available over both task views.');
assert.match(archivedRenderer, /archivedTaskSearch/);
assert.match(archivedRenderer, /archivedTaskStatus/);
assert.match(app, /window\.closeTaskDetailsModal = function \(\) \{[\s\S]*?classList\.remove\('active'\)/,
  'Closing details must close the overlay without navigating away.');
assert.doesNotMatch(app.slice(app.lastIndexOf('window.closeTaskDetailsModal = function () {'), app.indexOf('\n};', app.lastIndexOf('window.closeTaskDetailsModal = function () {'))), /renderView\(/,
  'Closing task details must not rerender or navigate the archive list.');

assert.match(detailsTab, /const canManageTask = !task\.archived_at &&/,
  'Archived tasks must not show the Add subtask action.');
assert.match(detailsTab, /const canChangeSubtask = !task\.archived_at && canChangeTaskStageRecord\(subtask\)/,
  'Archived task context must not expose subtask status controls.');
assert.match(app, /const canManageTaskFileSharing = !task\.archived_at &&/,
  'Archived tasks must not expose attachment-sharing mutation controls.');
assert.match(app, /const showCrmDesignDealStatus = !task\.archived_at &&/,
  'Archived tasks must not expose CRM status mutation controls.');
assert.match(subtaskComposer, /if \(!task \|\| task\.archived_at \|\| !host\) return/,
  'Archived tasks must reject opening the subtask composer.');
assert.match(subtaskSubmit, /if \(!parent \|\| parent\.archived_at\) return/,
  'Archived tasks must reject subtask submission.');
assert.match(app, /window\.toggleSubtaskComplete = async function \(subtaskId, iconEl\) \{\s*if \(window\.activeTaskDetail\?\.archived_at\) return;/,
  'Archived task context must reject subtask status changes.');
assert.match(app, /const canUploadFiles = canInteractWithTask\(task\)/,
  'Archived tasks must not expose task attachment uploads.');
assert.match(app, /if \(commentForm\) commentForm\.style\.display = canInteractWithTask\(task\) \? 'grid' : 'none'/,
  'Archived tasks must not expose the comment composer.');
assert.match(app, /if \(!canInteractWithTask\(window\.activeTaskDetail\) \|\| String\(window\.activeTaskDetail\?\.id\) !== String\(id\)\)/,
  'Comment submission must remain blocked for archived tasks.');
assert.match(app, /if \(!task \|\| task\.archived_at \|\| !canMq08ChangeCrmDesignDealStatus\(task\)\)/,
  'The CRM status handler must reject archived task edits.');

assert.match(modal, /!task\.archived_at && !isMq20Profile\(\)/,
  'Active task create controls retain their existing permission path.');
assert.match(app, /const canEdit = !task\.archived_at && canEditTaskRecord\(task\)/,
  'Active task editing remains controlled by existing permissions.');
assert.match(app, /const canCompleteAndHandOff = !task\.archived_at && canChangeTaskStageRecord\(task\)/,
  'Active task status actions remain controlled by existing permissions.');

console.log('Archived-task view persistence and read-only controls passed.');
