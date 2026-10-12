const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const harness = fs.readFileSync(path.join(root, 'supabase/staging/project-operations-phase-1-acceptance-test.ps1'), 'utf8');
const securitySql = fs.readFileSync(path.join(root, 'supabase/staging/project-operations-phase-1-security-catalog-check.sql'), 'utf8');
const phase1Sql = fs.readFileSync(path.join(root, 'supabase/migrations/20261002090000_project_operations_phase_1.sql'), 'utf8');

assert.match(harness, /jcfyyxsuspukcmybyhjj/);
assert.match(harness, /bbbetcdioiaozdjkvwxu/);
assert.match(harness, /Get-Content -Raw -LiteralPath \$LinkPath/);
assert.match(harness, /VERCEL_STAGING_ANON_KEY/);
assert.match(harness, /Read-Host[\s\S]*-AsSecureString/);
for (const identity of ['TEST-MANAGER', 'TEST-EMPLOYEE', 'TEST-OUTSIDER']) assert.match(harness, new RegExp(identity));
for (const rpc of [
  'create_project_secure', 'delete_project_secure', 'create_task_secure', 'delete_task_secure',
  'create_task_dependency', 'remove_task_dependency', 'get_project_operational_summary',
  'get_project_completion_readiness', 'change_project_status', 'complete_task_productivity',
  'start_task', 'mark_task_waiting', 'mark_task_blocked', 'resume_task',
]) assert.match(harness, new RegExp(rpc));
assert.doesNotMatch(harness, /service_role|service-role|SUPABASE_SERVICE_ROLE/);
assert.doesNotMatch(harness, /Invoke-Http\s+'(POST|PATCH|PUT|DELETE)'\s+['"]\/rest\/v1\/(projects|tasks|task_dependencies)/i);
assert.match(harness, /archived_at IS NULL/);
assert.match(harness, /NOT_TESTED_NO_AUTHORIZED_PER_TASK_ARCHIVE_RPC/);
assert.match(securitySql, /^\s*--[^\r\n]*\r?\nWITH\b/i);
assert.doesNotMatch(securitySql, /(?:^|;)\s*(?:INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|GRANT|REVOKE|NOTIFY)\b/im);
assert.match(phase1Sql, /COUNT\(\*\)[\s\S]*?AND task\.archived_at IS NULL/);

console.log('Project Operations Phase 1 staging acceptance harness contract tests passed.');
