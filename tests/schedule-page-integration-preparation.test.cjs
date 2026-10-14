/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const harness = read('supabase/staging/schedule-page-access-readiness-test.ps1');
const rollback = read('supabase/staging/rollback-schedule-page-backend-authorization.sql');

assert.match(harness, /param\([\s\S]*\[Parameter\(Mandatory = \$true\)\][\s\S]*\[string\]\$StagingProjectRef[\s\S]*\)/, 'Staging project identity must be supplied explicitly');
assert.match(harness, /\$ExpectedStagingRef = 'jcfyyxsuspukcmybyhjj'/, 'The approved staging identity is pinned');
assert.match(harness, /\$ProductionRef = 'bbbetcdioiaozdjkvwxu'/, 'Production is identified for an explicit refusal');
assert.match(harness, /\$TargetRef -ceq \$ProductionRef -or \$TargetRef -cne \$ExpectedStagingRef/, 'Incorrect or Production project identities fail before any CLI or HTTP operation');
assert.match(harness, /\$linked -cne \$TargetRef -or \$linked -ceq \$ProductionRef/, 'The local Supabase link must match the explicit staging identity');
const projectGuard = harness.indexOf('$TargetRef -ceq $ProductionRef -or $TargetRef -cne $ExpectedStagingRef');
const keyLoad = harness.indexOf('$keys = Invoke-SupabaseCliJson');
assert.ok(projectGuard >= 0 && keyLoad > projectGuard, 'Project identity is rejected before service credentials are loaded');

for (const identity of ['TEST-ADMIN', 'TEST-EMPLOYEE', 'TEST-OUTSIDER']) {
  assert.match(harness, new RegExp(identity), `${identity} is required as a dedicated synthetic identity`);
}
assert.match(harness, /\[string\]\$adminProfile\.role -cne 'ADMIN'/, 'The synthetic administrator role is verified');
assert.match(harness, /Dedicated synthetic staging profiles are missing or duplicated/, 'Missing or ambiguous synthetic identities abort safely');
assert.match(harness, /HR_SYS_STAGING_TEST_ADMIN_TOKEN/);
assert.match(harness, /HR_SYS_STAGING_TEST_EMPLOYEE_TOKEN/);
assert.match(harness, /HR_SYS_STAGING_TEST_OUTSIDER_TOKEN/);
assert.match(harness, /Raw GET "\$base\/auth\/v1\/user"/, 'Every ephemeral token is resolved to its authenticated user');
assert.match(harness, /\[string\]\$identity\.id -cne \[string\]\$profile\.id/, 'Token identity must match the dedicated profile UUID');

assert.doesNotMatch(harness, /auth\/v1\/admin\/users/, 'The harness must not call Auth administrator credential endpoints');
assert.doesNotMatch(harness, /grant_type=password|New-Password|email_confirm|\bpassword\b/i, 'The harness must not create, accept, or reset passwords');
assert.doesNotMatch(harness, /Raw PUT/, 'The harness has no credential update request');
assert.doesNotMatch(harness, /Write-Output[^\r\n]*(?:token|service|anon)|Set-Content|Add-Content|Out-File/i, 'Credentials are neither printed nor persisted');

assert.match(harness, /\$permissionSnapshots\.user/);
assert.match(harness, /\$permissionSnapshots\.role/);
assert.match(harness, /\$permissionSnapshots\.department/);
assert.match(harness, /finally \{/);
assert.match(harness, /allowed_pages=@\(\$entry\.rows\[0\]\.allowed_pages\)/, 'Existing permission rows are restored');
assert.match(harness, /Raw DELETE \$entry\.url/, 'Permission rows created only for the fixture are removed');
assert.match(harness, /is_active=\[bool\]\$subject\.is_active/, 'Synthetic profile activity is restored');
assert.match(harness, /foreach \(\$id in \$createdReminderIds\)[\s\S]*Raw DELETE/, 'Synthetic reminders are removed');
assert.match(harness, /if \(\$cleanupFailed\)[\s\S]*exit 1/, 'Cleanup failure is visible and fails the run');
assert.ok((harness.match(/Require-Success \(Raw/g) || []).length >= 10, 'Fixture mutations fail fast and enter cleanup');

assert.match(rollback, /^-- MANUAL STAGING ROLLBACK ONLY\./, 'Rollback is explicitly manual and staging-scoped');
assert.match(rollback, /Pause every push-notification-dispatcher invocation[\s\S]*Apply this rollback[\s\S]*Deploy the dispatcher version[\s\S]*resume dispatch invocations/, 'Safe dispatcher rollback order is documented');
for (const operation of ['SELECT', 'INSERT', 'UPDATE', 'DELETE']) {
  assert.match(rollback, new RegExp(`CREATE POLICY "Users can \\w+ their reminders"[\\s\\S]*?FOR ${operation} TO authenticated`), `${operation} ownership policy is restored`);
}
assert.equal((rollback.match(/user_id = auth\.uid\(\)/g) || []).length, 5, 'Every restored policy clause retains ownership isolation');
assert.doesNotMatch(rollback, /has_my_page_access\('schedule'\)/, 'Rollback removes Schedule permission from reminder RLS');

const listDrop = rollback.indexOf('DROP FUNCTION IF EXISTS public.list_due_schedule_reminders_for_dispatch(integer)');
const wrapperDrop = rollback.indexOf('DROP FUNCTION IF EXISTS public.has_my_page_access(text)');
const internalDrop = rollback.indexOf('DROP FUNCTION IF EXISTS public.has_effective_page_access_internal(uuid, text)');
assert.ok(listDrop >= 0 && wrapperDrop > listDrop && internalDrop > wrapperDrop, 'Authorization functions are removed in dependency-safe order');
assert.doesNotMatch(rollback, /\bCASCADE\b/i, 'Rollback cannot cascade into unrelated objects');
assert.doesNotMatch(rollback, /\b(?:INSERT INTO|UPDATE|DELETE FROM|TRUNCATE)\s+public\.(?:reminders|user_permissions|role_permissions)\b/i, 'Rollback does not rewrite reminder or permission records');
assert.doesNotMatch(rollback, /\b(?:DROP TABLE|ALTER TABLE|TRUNCATE)\b/i, 'Rollback does not alter unrelated table structures');
assert.match(rollback, /BEGIN;[\s\S]*COMMIT;/, 'Rollback is transactional');

console.log('Schedule integration preparation security checks passed (static only; no staging services contacted).');
