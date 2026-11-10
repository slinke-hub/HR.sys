const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261110100000_crm_staging_compatibility_security.sql'), 'utf8');
const crmMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20261109100000_crm_contact_discussion_automation.sql'), 'utf8');
const mq20Migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261109110000_mq20_contact_discussion_execution.sql'), 'utf8');

assert.match(migration, /d7a69cae93a7ca717e766b853a940b82/);
assert.match(migration, /ec2fc0ab26cc97d2cfce2509b2e20bc8/);
assert.match(migration, /3fa1d8615f9d9222519ef50757abdb0b/);
assert.match(migration, /2ff4140400da5c8afe992409ab714eba/);
assert.match(migration, /1cf17344666c71d4ec9acf22280554ef/);
assert.match(migration, /current_user <> 'postgres'/);
assert.match(migration, /profile\.is_activeisdistinctfromfalse/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.is_mq20_current_user\(\)/);
assert.match(migration, /SELECT auth\.uid\(\) IS NOT NULL AND public\.is_mq20_profile\(auth\.uid\(\)\)/);
assert.match(migration, /ALTER POLICY %I ON %I\.%I USING/);
assert.match(migration, /ALTER POLICY %I ON %I\.%I WITH CHECK/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.is_mq20_profile\(uuid\) FROM PUBLIC, anon, authenticated/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.is_mq20_profile\(uuid\) TO service_role/);
assert.match(migration, /An unreviewed authenticated RPC can reach the MQ-20 membership helper/);
assert.match(migration, /Task grant RPC no longer requires the authorized Marketing Manager context/);
assert.match(migration, /caller-scoped authorization boundary/);
assert.match(migration, /upper\(btrim\(coalesce\(profile\.employee_id,/);
assert.match(migration, /NEW\.stage = 'LOST'[\s\S]*A lost reason is required/);
assert.doesNotMatch(migration, /Discussion is no longer an active CRM stage/);
assert.match(migration, /task\.archived_at IS NULL/);
assert.match(migration, /UPPER\(COALESCE\(deal\.stage, ''\)\) <> 'LOST'/);
assert.match(migration, /p_user_id = ANY\(assignment\.current_assignees\)/);
assert.match(migration, /task\.assignee_ids[\s\S]*assignment\.current_assignees/);
assert.match(migration, /task\.visible_to[\s\S]*assignment\.current_assignees/);
assert.match(migration, /generated\.kind = 'CONTACT_DISCUSSION'/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.decide_crm_design_task_approval\(uuid, text, text\) FROM PUBLIC, anon/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.decide_crm_design_task_approval\(uuid, text, text\) TO authenticated/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.queue_task_notification\(uuid, uuid, text, text\) FROM PUBLIC, anon, authenticated/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.queue_task_notification\(uuid, uuid, text, text\) TO service_role/);
assert.match(migration, /caller\.prosrc ILIKE '%queue_task_notification%'[\s\S]*NOT caller\.prosecdef/);
assert.match(migration, /NOTIFY pgrst, 'reload schema'/);

// Earlier reviewed migrations remain unchanged and this correction follows them.
assert.match(crmMigration, /assignee_ids uuid\[\]/);
assert.match(mq20Migration, /CREATE OR REPLACE FUNCTION public\.execute_crm_contact_discussion_task/);
assert.ok('20261110100000_crm_staging_compatibility_security.sql' > '20261109110000_mq20_contact_discussion_execution.sql');

console.log('PASS: compatibility migration is narrowly scoped, drift guarded, and preserves the approved CRM/MQ-20 migration order.');
