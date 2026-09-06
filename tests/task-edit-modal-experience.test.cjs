/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const app = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, '..', 'css', 'components.css'), 'utf8');

const modalStart = html.indexOf('<div class="modal" id="editTaskModal">');
const modalEnd = html.indexOf('<!-- Task Details & Comments Side Panel -->', modalStart);
assert.ok(modalStart >= 0 && modalEnd > modalStart, 'Edit task modal was not found');
const modal = html.slice(modalStart, modalEnd);
const advancedStart = modal.indexOf('id="editTaskTabAdvanced"');
const advancedEnd = modal.indexOf('<!-- Footer -->', advancedStart);
const advanced = modal.slice(advancedStart, advancedEnd);

assert.match(modal, /class="edit-task-top-row"[\s\S]*editTaskMoveList[\s\S]*editTaskDue/);
assert.match(modal, /class="edit-task-grid edit-task-details-grid"/);
assert.match(modal, /editTaskEstimate[\s\S]*editTaskPriority[\s\S]*editTaskVisibility[\s\S]*editTaskCategory/);
assert.match(advanced, /id="editTaskDepartment"/);
assert.doesNotMatch(advanced, /editTaskReminders|editTaskWatchers|editTaskRepeat|ui_reminders|ui_followers|ui_set_to_repeat2/);

assert.match(css, /\.edit-task-v2 \.edit-task-top-row \{[^}]*grid-template-columns:/);
assert.match(css, /\.edit-task-v2 \.edit-task-details-grid \.edit-task-assignee-cell \{ grid-column: 1 \/ -1; \}/);

const editSubmitStart = app.indexOf('window.handleEditTaskSubmit = async function');
const editSubmitEnd = app.indexOf('window.handleDeleteTask = async function', editSubmitStart);
const editSubmit = app.slice(editSubmitStart, editSubmitEnd);
assert.doesNotMatch(editSubmit, /db\.fetchUsers\(\)|db\.fetchDepartments\(\)/);
assert.doesNotMatch(editSubmit, /await renderView\(/);
assert.match(editSubmit, /patchCachedTaskNodes\(updatedTask\)/);
assert.match(editSubmit, /window\.scheduleTaskWorkspaceRefresh\(250\)/);

const subtaskStart = app.indexOf('window.openInlineSubtaskComposer = function');
const subtaskEnd = app.indexOf('window.taskV2ChangeStage = async function', subtaskStart);
const subtasks = app.slice(subtaskStart, subtaskEnd);
assert.match(subtasks, /inlineSubtaskRows/);
assert.match(subtasks, /window\.addInlineSubtaskRow/);
assert.match(subtasks, /Promise\.all\(entries\.map/);
assert.match(subtasks, /successful\.forEach\(result => cacheTaskRecord\(result\.data\)\)/);

console.log('Task edit modal experience tests passed.');
