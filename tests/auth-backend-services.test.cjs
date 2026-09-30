/* Static Auth/session contract and security regression checks. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

const sql = read('supabase/staging/auth_backend_services.sql');
const db = read('js/db.js');
const app = read('js/app.js');
const bridge = read('js/shared-services.js');
const contract = read('src/shared/auth-contract.ts');
const readinessScript = read('supabase/staging/auth-readiness-test.ps1');

for (const fn of ['admin_get_user_email', 'admin_update_user_credentials', 'admin_reset_user_password', 'admin_set_user_lock']) {
  assert.match(sql, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}`));
  assert.match(sql, new RegExp(`GRANT EXECUTE ON FUNCTION[\\s\\S]*${fn}`));
}
assert.match(sql, /is_active IS DISTINCT FROM FALSE/);
assert.match(sql, /REVOKE ALL ON FUNCTION public\.reset_user_password\(uuid, text\) FROM PUBLIC, anon, authenticated/);
assert.match(sql, /admin_password_reset_audit/);
assert.doesNotMatch(sql, /INSERT\s+INTO\s+auth\.users/i);
assert.doesNotMatch(sql, /password\s*[:=]\s*['"][^'"]+['"]/i);

assert.match(db, /async signInSession\(/);
assert.match(db, /auth\.getUser\(\)/);
assert.match(db, /async getCurrentUserProfile\(/);
assert.match(db, /eq\('id', user\.id\)/);
assert.match(db, /admin_reset_user_password/);
assert.doesNotMatch(db, /functions\.invoke\('admin-set-user-password'/);
assert.doesNotMatch(app, /privatepple@gmail\.com/);
assert.match(app, /getCurrentUserProfile\(\)/);
assert.match(bridge, /getCurrentProfile/);
for (const method of ['updatePassword', 'getCurrentProfile', 'refreshSession']) assert.match(contract, new RegExp(method));

const functionSources = [
  'supabase/functions/file-signed-url/index.ts',
  'supabase/functions/document-expiry-notifier/index.js',
  'supabase/functions/push-notification-dispatcher/index.ts',
  'supabase/functions/task-notification-email/index.js',
].map(read);
for (const source of functionSources) {
  assert.doesNotMatch(source, /Access-Control-Allow-Origin['"]\s*:\s*['"]\*['"]/i);
  assert.doesNotMatch(source, /console\.(log|info)\([^\n]*(access|refresh)[_-]?token/i);
}
assert.match(functionSources[0], /auth\.getUser/);
assert.match(functionSources[1], /auth\.getUser/);
assert.match(functionSources[2], /auth\.getUser/);
assert.match(functionSources[3], /auth\.getUser/);

const forbiddenClientSecrets = /SUPABASE_SERVICE_ROLE_KEY|SUPABASE_SECRET_KEY|RESEND_API_KEY|VAPID_PRIVATE_KEY|TASK_EMAIL_DISPATCH_SECRET|PUSH_DISPATCH_SECRET/;
assert.doesNotMatch(db, forbiddenClientSecrets);
assert.doesNotMatch(app, forbiddenClientSecrets);
assert.doesNotMatch(bridge, forbiddenClientSecrets);
assert.match(readinessScript, /jcfyyxsuspukcmybyhjj/);
assert.doesNotMatch(readinessScript, /bbbetcdioiaozdjkvwxu\s*\./);
assert.match(readinessScript, /RandomNumberGenerator/);
assert.match(readinessScript, /TEST-MANAGER/);
assert.match(readinessScript, /Where-Object id -eq \$profile\.id/);
assert.match(readinessScript, /UseBasicParsing\s*=\s*\$true/);
assert.doesNotMatch(readinessScript, /password\s*=\s*['"][^'"]+['"]/i);

console.log('Auth backend contract and security checks passed.');
