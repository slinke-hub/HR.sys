const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const harness = read('supabase/staging/s3-authenticated-acceptance.ps1');
const edge = read('supabase/functions/secure-login/index.ts');
const db = read('js/db.js');
const config = read('supabase/config.toml');

test('S3 acceptance harness is staging-only and makes isolated disposable fixtures', () => {
  assert.match(harness, /\$TargetRef = 'jcfyyxsuspukcmybyhjj'/);
  assert.match(harness, /\$ProductionRef = 'bbbetcdioiaozdjkvwxu'/);
  assert.match(harness, /linked -ceq \$ProductionRef -or \$linked -cne \$TargetRef/);
  for (const fixture of ['USER', 'ACTIVE-ADMIN', 'INACTIVE-ADMIN', 'DELETE-TARGET']) {
    assert.ok(harness.includes(`New-Fixture '${fixture}'`), `missing isolated fixture ${fixture}`);
  }
  assert.match(harness, /employeeId = "S3A-\$\(\$script:RunId\)-\$Label"/);
  assert.match(harness, /finally\s*\{\s*Cleanup-Fixtures/s);
  assert.match(harness, /\$script:Passwords\.Clear\(\)/);
  assert.match(harness, /Read-Host .* -AsSecureString/);
  assert.doesNotMatch(harness, /Write-(?:Host|Output).*\$script:(?:ServiceKey|Passwords|AccessTokens)/);
});

test('acceptance covers anonymous, ordinary, active/inactive admin, delete and trusted service paths', () => {
  for (const expected of [
    'ANON_LOGIN_ATTEMPTS_READ', 'AUTH_LOGIN_ATTEMPTS_READ',
    'ANON_LOGIN_ATTEMPTS_INSERT', 'AUTH_LOGIN_ATTEMPTS_INSERT',
    'ANON_LOGIN_ATTEMPTS_UPDATE', 'AUTH_LOGIN_ATTEMPTS_UPDATE',
    'ANON_LOGIN_ATTEMPTS_DELETE', 'AUTH_LOGIN_ATTEMPTS_DELETE',
    'ANON_RECORD_FAILED_LOGIN_RPC', 'AUTH_RECORD_FAILED_LOGIN_RPC',
    'ORDINARY_RESET_SELF', 'ORDINARY_RESET_OTHER_USER',
    'ACTIVE_ADMIN_RESET_OTHER', 'INACTIVE_ADMIN_RESET',
    'ORDINARY_DELETE_USER_RPC', 'INACTIVE_ADMIN_DELETE',
    'ACTIVE_ADMIN_DELETE_DISPOSABLE_TARGET', 'TRUSTED_FAILED_LOGIN_PATH',
    'LOGIN_LOCKOUT_ENFORCEMENT',
  ]) assert.ok(harness.includes(expected), `missing acceptance case ${expected}`);
  assert.match(harness, /UNEXPECTED_AUTHORIZATION_RESULT/);
  assert.match(harness, /INFRASTRUCTURE_FAILURE/);
  assert.match(harness, /Cleanup-Fixtures/);
});

test('browser delegates authentication to secure-login and receives no privileged credential path', () => {
  assert.match(db, /functions\/v1\/secure-login/);
  assert.match(db, /auth\.setSession\(/);
  assert.doesNotMatch(db, /auth\.signInWithPassword\(/);
  assert.doesNotMatch(db, /recordFailedLogin|\.rpc\(['"]record_failed_login/);
  assert.doesNotMatch(db, /\.from\(['"]login_attempts['"]\)/);
  assert.doesNotMatch(db, /SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY/);
  assert.match(config, /\[functions\.secure-login\][\s\S]*?verify_jwt = false/);
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(edge, /trustedClient\.rpc\("record_failed_login"/);
  assert.match(edge, /trustedClient[\s\S]*?from\("login_attempts"\)[\s\S]*?locked_until/);
  assert.doesNotMatch(edge, /console\.(?:log|info|warn|error)\s*\(/);
  assert.doesNotMatch(edge, /Access-Control-Allow-Origin['"]\s*:\s*['"]\*['"]/i);
});
