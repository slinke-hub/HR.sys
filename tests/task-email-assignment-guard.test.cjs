const assert = require('node:assert/strict');
const fs = require('node:fs');

const worker = fs.readFileSync('supabase/functions/task-notification-email/index.js', 'utf8');
const migration = fs.readFileSync(
  'supabase/migrations/20261107100000_assignee_task_notifications_and_sound_preferences.sql',
  'utf8'
);

assert.match(worker, /select\("id,notification_id,task_id,recipient_id,recipient_email/);
assert.match(worker, /\.from\("profiles"\)\.select\("id,role"\)\.in\("id", recipientIds\)/);
assert.match(worker, /role !== "EMPLOYEE"\) return false/);
assert.match(worker, /task\.assignee_id !== item\.recipient_id && !multipleAssignees\.includes\(item\.recipient_id\)/);
assert.match(worker, /status: "cancelled",\s+last_error: "Task email recipient is not currently assigned to the task\."/);
assert.match(worker, /if \(suppressError\) return json\(\{ error: "Unable to suppress task emails for unassigned employees" \}, 500\)/);

assert.match(migration, /CREATE TRIGGER employee_task_email_assignment_guard\s+BEFORE INSERT ON public\.task_email_outbox/);
assert.match(migration, /CREATE POLICY employee_task_notification_assignment_read_guard\s+ON public\.notifications\s+AS RESTRICTIVE\s+FOR SELECT TO authenticated/);

console.log('Task-linked email and direct notification reads are assignment-scoped.');
