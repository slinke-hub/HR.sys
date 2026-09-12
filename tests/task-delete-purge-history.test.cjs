/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260912170000_purge_task_history_on_delete.sql'), 'utf8');

// 1. Verify SQL migration purges dependent records on task delete
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.clean_task_history_on_delete/);
assert.match(migration, /DELETE FROM public\.task_attachments WHERE task_id = OLD\.id/);
assert.match(migration, /DELETE FROM public\.task_comments WHERE task_id = OLD\.id/);
assert.match(migration, /DELETE FROM public\.task_email_outbox WHERE task_id = OLD\.id/);
assert.match(migration, /DELETE FROM public\.notifications[\s\S]*WHERE task_id = OLD\.id/);
assert.match(migration, /CREATE TRIGGER trg_clean_task_history_on_delete/);
assert.match(migration, /BEFORE DELETE ON public\.tasks/);

// 2. Verify db.uploadTaskAttachment records to task_attachments table
assert.match(db, /uploadTaskAttachment\(taskId,\s*userId,\s*file\)/);
assert.match(db, /supabaseClient[\s\S]*?\.from\('task_attachments'\)[\s\S]*?\.insert/);

// 3. Verify db.deleteTaskAttachmentObjects supports multiple storage buckets
assert.match(db, /deleteTaskAttachmentObjects\(references\)/);
assert.match(db, /pathsByBucket\[parsed\.bucket\]/);

// 4. Verify db.deleteTask gathers all files and purges storage and database history
assert.match(db, /async deleteTask\(taskId\)/);
assert.match(db, /\.select\('id,\s*title,\s*file_links,\s*submission_links,\s*content_links,\s*upload_link'\)/);
assert.match(db, /\.from\('task_comments'\)[\s\S]*?\.select\('attachments'\)/);
assert.match(db, /\.from\('task_attachments'\)[\s\S]*?\.select\('file_url'\)/);
assert.match(db, /\.storage[\s\S]*?\.from\('hr-documents'\)[\s\S]*?\.remove/);
assert.match(db, /\.storage[\s\S]*?\.from\('task-attachments'\)[\s\S]*?\.remove/);
assert.match(db, /\.storage[\s\S]*?\.from\('task-attachments'\)[\s\S]*?\.list\(taskId/);
assert.match(db, /\.from\('task_attachments'\)[\s\S]*?\.delete\(\)[\s\S]*?\.eq\('task_id',\s*taskId\)/);
assert.match(db, /\.from\('task_comments'\)[\s\S]*?\.delete\(\)[\s\S]*?\.eq\('task_id',\s*taskId\)/);
assert.match(db, /\.from\('task_email_outbox'\)[\s\S]*?\.delete\(\)[\s\S]*?\.eq\('task_id',\s*taskId\)/);
assert.match(db, /\.from\('notifications'\)[\s\S]*?\.delete\(\)[\s\S]*?\.eq\('task_id',\s*taskId\)/);
assert.match(db, /\.from\('tasks'\)[\s\S]*?\.delete\(\)[\s\S]*?\.eq\('id',\s*taskId\)/);

// 5. Verify window.closeTaskDetailsModal resets activeTaskDetail and file list DOM
assert.match(app, /window\.closeTaskDetailsModal = function/);
assert.match(app, /window\.activeTaskDetail = null/);
assert.match(app, /detailsTaskId\.value = ''/);
assert.match(app, /taskDetailFileList/);

// 6. Verify window.handleDeleteTask clears modals and file input state
assert.match(app, /window\.handleDeleteTask = async function/);
assert.match(app, /const \{ error \} = await db\.deleteTask\(id\)/);
assert.match(app, /window\.closeTaskDetailsModal\?\.(\(\))/);
assert.match(app, /createFileInput.*\.value = ''/);
assert.match(app, /createFileList.*\.innerHTML = ''/);

// 7. Verify window.closeCreateTaskModal clears file input and file list
const closeCreateStart = app.indexOf('window.closeCreateTaskModal = function');
const closeCreateEnd = app.indexOf('window.handleTaskDepartmentChange', closeCreateStart);
assert.ok(closeCreateStart >= 0 && closeCreateEnd > closeCreateStart, 'closeCreateTaskModal was found');
const closeCreateSnippet = app.slice(closeCreateStart, closeCreateEnd);
assert.match(closeCreateSnippet, /createTaskFileInput/);
assert.match(closeCreateSnippet, /createTaskFileList/);

// 8. Verify window.handleCreateTask uploads attachments and clears inputs
const handleCreateStart = app.indexOf('window.handleCreateTask = async function');
const handleCreateEnd = app.indexOf('function isDailyRepeatingTask', handleCreateStart);
assert.ok(handleCreateStart >= 0 && handleCreateEnd > handleCreateStart, 'handleCreateTask was found');
const handleCreateSnippet = app.slice(handleCreateStart, handleCreateEnd);
assert.match(handleCreateSnippet, /db\.uploadTaskAttachment\(createdTask\.id/);
assert.match(handleCreateSnippet, /createFileInput.*\.value = ''/);
assert.match(handleCreateSnippet, /createFileList.*\.innerHTML = ''/);

console.log('Task delete history purge tests passed successfully.');
