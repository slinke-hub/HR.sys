/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261109110000_mq20_contact_discussion_execution.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.execute_crm_contact_discussion_task/);
for (const action of ['START', 'WAIT', 'BLOCK', 'RESUME', 'COMPLETE']) assert.match(migration, new RegExp(`'${action}'`));
assert.match(migration, /public\.is_mq20_profile\(auth\.uid\(\)\)/);
assert.match(migration, /auth\.uid\(\) = ANY\(v_assignees\)/);
assert.match(migration, /crm_generated_tasks mapping[\s\S]*mapping\.kind = 'CONTACT_DISCUSSION'/);
assert.match(migration, /task\.archived_at IS NOT NULL/);
assert.match(migration, /FROM public\.crm_deals WHERE id = v_initial_deal_id FOR UPDATE;[\s\S]*FROM public\.tasks WHERE id = p_task_id FOR UPDATE/,
  'Execution must lock deal before task, matching assignment synchronization.');
assert.match(migration, /CREATE TRIGGER crm_sync_contact_discussion_assignees[\s\S]*AFTER UPDATE OF assigned_to, assignee_ids ON public\.crm_deals/);
assert.match(migration, /SET assignee_id = v_assignees\[1\], assignee_ids = v_assignees, visible_to = v_assignees/);
assert.match(migration, /backend_pid = pg_backend_pid\(\)[\s\S]*transaction_id = txid_current\(\)[\s\S]*actor_id IS NOT DISTINCT FROM auth\.uid\(\)/);
assert.match(migration, /REVOKE ALL ON TABLE hrsys_private\.mq20_task_write_context FROM PUBLIC, anon, authenticated, service_role/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.execute_crm_contact_discussion_task[\s\S]*FROM PUBLIC, anon, service_role/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.execute_crm_contact_discussion_task[\s\S]*TO authenticated/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.enforce_mq20_task_service_boundaries/);
assert.match(migration, /MQ-20 task access is view-only/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.protect_task_access_fields/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.notify_task_change/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.queue_task_status_notification/);
assert.match(migration, /is_mq20_notification_suppressed\(NEW\.id\)/);
const executionRpc = migration.match(/CREATE OR REPLACE FUNCTION public\.execute_crm_contact_discussion_task\([\s\S]*?\$function\$;/)?.[0] || '';
assert.ok(executionRpc, 'Scoped execution RPC body must be present.');
assert.doesNotMatch(executionRpc, /activate_task_successors|complete_task_productivity\(|change_task_status\(|queue_task_notification\(/,
  'Scoped execution must not activate successors or call notification-producing/general task RPCs.');
assert.doesNotMatch(migration, /CREATE POLICY|ALTER POLICY|DROP POLICY|DISABLE ROW LEVEL SECURITY/,
  'The migration must not alter or bypass existing RLS policies.');
assert.match(migration, /IF v_task\.archived_at IS NOT NULL THEN RAISE EXCEPTION/);

assert.match(app, /const canExecuteMq20ContactDiscussionTask = task =>[\s\S]*task\.crm_workflow_kind === 'CONTACT_DISCUSSION'[\s\S]*!task\.archived_at/);
assert.match(app, /else if \(canExecuteMq20ContactDiscussionTask\(task\)\)[\s\S]*'start'[\s\S]*'waiting'[\s\S]*'blocked'[\s\S]*'complete'/);
assert.match(app, /canExecuteMq20ContactDiscussionTask\(task\)\)[\s\S]*pending approval[\s\S]*actions = ''/i,
  'Approval-pending task controls must remain hidden.');
assert.match(app, /if \(isMq20Profile\(\) && \(!scopedMq20Task \|\| action === 'handoff'\)\)/);
assert.match(app, /db\.executeCrmContactDiscussionTask\(taskId, blocked \? 'BLOCK' : 'WAIT', category, note\)/);
assert.match(db, /async executeCrmContactDiscussionTask\(taskId, action, category = null, note = null\)/);
assert.match(db, /rpc\('execute_crm_contact_discussion_task'/);
assert.doesNotMatch(db.slice(db.indexOf('async executeCrmContactDiscussionTask'), db.indexOf('async startTask')),
  /flushTaskNotificationEmails/);

console.log('PASS: MQ-20 scoped Contact Discussion static security and UI regression assertions.');
