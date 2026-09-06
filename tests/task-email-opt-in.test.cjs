/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'task_email_creator_opt_in_migration.sql'), 'utf8');
const emailFunction = fs.readFileSync(path.join(root, 'supabase', 'functions', 'task-notification-email', 'index.js'), 'utf8');

const modalStart = app.indexOf('<!-- Create Task Modal -->');
const modalEnd = app.indexOf('<!-- Task List Management Modal -->', modalStart);
assert.ok(modalStart >= 0 && modalEnd > modalStart, 'Create-task modal template was not found');
const modal = app.slice(modalStart, modalEnd);

assert.match(modal, /for="taskDue">Due Date<\/label>/);
assert.match(modal, /<input[^>]*type="date"[^>]*id="taskDue"/);
assert.match(modal, /id="taskNotifyViaEmail"/);
assert.doesNotMatch(modal, /id="taskNotifyViaEmail"[^>]*checked/);

const handlerStart = app.indexOf('window.handleCreateTask = async function');
const handlerEnd = app.indexOf('function isDailyRepeatingTask', handlerStart);
const handler = app.slice(handlerStart, handlerEnd);
assert.match(handler, /document\.getElementById\('taskDue'\)\?\.value \|\| null/);
assert.match(handler, /document\.getElementById\('taskNotifyViaEmail'\)\?\.checked === true/);
assert.match(handler, /repeatInterval, notifyViaEmail\)/);

assert.match(db, /notifyViaEmail = false\)/);
assert.match(db, /notify_via_email: notifyViaEmail === true/);

assert.match(migration, /ADD COLUMN IF NOT EXISTS notify_via_email BOOLEAN NOT NULL DEFAULT FALSE/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS always_send BOOLEAN NOT NULL DEFAULT FALSE/);
assert.match(migration, /UPPER\(REPLACE\(COALESCE\(profile\.role, ''\), '_', ' '\)\)/);
assert.match(migration, /IN \('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'\)/);
assert.match(migration, /OR \(task_row\.notify_via_email IS TRUE AND profile\.task_email_notifications = TRUE\)/);
assert.match(migration, /profile\.task_email_notifications = TRUE/);
assert.match(migration, /outbox\.always_send IS NOT TRUE/);
assert.match(migration, /status = 'cancelled'/);

assert.match(emailFunction, /\.eq\("notify_via_email", true\)/);
assert.match(emailFunction, /attachment_links,always_send/);
assert.match(emailFunction, /item\.always_send === true \|\| \(item\.task_id && optedInTaskIds\.has\(item\.task_id\)\)/);
assert.match(emailFunction, /status: "cancelled"/);

console.log('Task email opt-in tests passed.');
