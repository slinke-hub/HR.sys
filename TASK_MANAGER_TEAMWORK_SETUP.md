# Task Manager workflow activation

The application code is ready, but the database and email worker must be activated in Supabase before the new permissions and notifications take effect.

## 1. Apply the database workflow

Open the Supabase SQL Editor for this project and run the complete contents of:

`tasks_teamwork_workflow_migration.sql`

This adds nested subtasks, task-level access control, comment access rules, notification events, and the email outbox.

Then run `marketing_design_tasks_migration.sql` to activate the Marketing Designing Task fields and multi-link storage.

## 2. Deploy the email worker

Deploy the Edge Function in:

`supabase/functions/task-notification-email/index.js`

Keep JWT verification enabled. Configure these function secrets:

- `RESEND_API_KEY`: API key from Resend.
- `TASK_EMAIL_FROM`: a verified sender, for example `MUQAM Tasks <tasks@your-domain.com>`.
- `APP_URL`: the public URL of the HR application, without a trailing slash.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are supplied by Supabase to hosted Edge Functions.

## 3. Verification checklist

1. Create a private main task and confirm an unrelated employee cannot see it.
2. Add an employee as a watcher and confirm the task becomes visible to that employee.
3. Open the main task and add a subtask inline; confirm it appears inside the parent.
4. Comment as a viewer and confirm the creator, assignee, supervisor, watchers, and previous participants receive an in-app notification.
5. Click a task notification and confirm it opens the task details.
6. Confirm the same notification reaches the recipient by email.

Email delivery is non-blocking: if the email service is unavailable, task creation and comments continue to work and the failure remains recorded in `task_email_outbox`.
