const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const migrationPath = path.join(root, 'supabase/migrations/20261104120000_archived_task_write_protection.sql');
const migration = fs.readFileSync(migrationPath, 'utf8');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.guard_archived_task_row_write\(\)/i);
assert.match(migration, /OLD\.archived_at IS NULL/i);
assert.match(migration, /NEW\.archived_at IS NULL[\s\S]*can_assign_tasks_company_wide\(v_actor\)/i,
  'Admin restore is limited to the company-wide admin predicate.');
assert.match(migration, /to_jsonb\(NEW\) - 'archived_at' - 'updated_at'[\s\S]*to_jsonb\(OLD\) - 'archived_at' - 'updated_at'/i,
  'Restore must not alter archived task content.');
assert.match(migration, /Archived tasks are read-only/i);
assert.match(migration, /auth\.role\(\) = 'service_role' OR session_user IN \('postgres', 'service_role'\)/i);

for (const table of [
  'tasks', 'task_comments', 'task_attachments', 'task_activity',
  'task_dependencies', 'task_waiting_history', 'task_blocker_history',
]) {
  assert.match(migration, new RegExp(`ON public\\.${table}\\b`, 'i'), `${table} guard is installed`);
}

assert.match(migration, /predecessor_task_id[\s\S]*successor_task_id/i,
  'Dependency guard checks both endpoints.');
assert.match(migration, /FOR UPDATE/i, 'Parent checks lock task rows against concurrent archival.');
for (const operation of ['insert', 'update', 'delete']) {
  assert.match(migration, new RegExp(`task_attachment_storage_active_parent_${operation}[\\s\\S]*?ON storage\\.objects AS RESTRICTIVE FOR ${operation.toUpperCase()}`, 'i'),
    `Storage ${operation} remains limited to an active, authorized parent task.`);
}
assert.match(migration, /IF TG_OP = 'DELETE' THEN RETURN OLD;[\s\S]*Task not found/i,
  'Existing orphan-child cleanup remains possible only for DELETE.');
assert.match(migration, /REVOKE ALL ON FUNCTION public\.archive_completed_tasks\(\) FROM PUBLIC, anon, authenticated;[\s\S]*GRANT EXECUTE ON FUNCTION public\.archive_completed_tasks\(\) TO service_role;/i,
  'Bulk archive remains maintenance-only and service-role callable.');

for (const fn of ['guard_archived_task_row_write', 'guard_archived_task_child_write']) {
  assert.match(migration, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\(\\) FROM PUBLIC, anon, authenticated;`, 'i'));
}

console.log('Archived task write-protection migration static assertions passed.');
