const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261005110000_security_hardening_s3.sql'), 'utf8');
const appDb = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const secureLogin = fs.readFileSync(path.join(root, 'supabase/functions/secure-login/index.ts'), 'utf8');
const config = fs.readFileSync(path.join(root, 'supabase/config.toml'), 'utf8');

function methodBody(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  assert.notEqual(start, -1, `missing method: ${startMarker}`);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert.notEqual(end, -1, `missing method boundary: ${endMarker}`);
  return source.slice(start, end);
}

test('S3 is an atomic, scoped forward migration with fail-closed prerequisites', () => {
  assert.match(migration, /^BEGIN;/m);
  assert.match(migration, /COMMIT;\s*$/m);
  assert.match(migration, /to_regclass\('public\.login_attempts'\)/);
  assert.match(migration, /to_regprocedure\('public\.record_failed_login\(text\)'\)/);
  assert.match(migration, /to_regprocedure\('public\.reset_login_lockout\(text\)'\)/);
  assert.match(migration, /DROP POLICY IF EXISTS "Anyone can read login attempts"/);
  assert.match(migration, /REVOKE ALL PRIVILEGES ON TABLE public\.login_attempts FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /REVOKE ALL PRIVILEGES \(email, attempts, locked_until\)/);
  assert.doesNotMatch(migration, /\b(?:INSERT INTO|DELETE FROM|TRUNCATE|DROP TABLE|ALTER TABLE .*DROP)\b/i);
  assert.doesNotMatch(migration, /supabase_migrations|schema_migrations/i);
});

test('pre-auth failed-login RPC is removed from ordinary clients and reserved for service role', () => {
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.record_failed_login\(text\) FROM PUBLIC, anon, authenticated/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.record_failed_login\(text\) TO service_role/);
  assert.match(migration, /record_failed_login\(text\)\s+SET search_path = pg_catalog, public, pg_temp/s);
  assert.doesNotMatch(app, /recordFailedLogin|\.rpc\(['"]record_failed_login/);
  assert.doesNotMatch(appDb, /recordFailedLogin|\.rpc\(['"]record_failed_login/);
  assert.doesNotMatch(appDb, /from\(['"]login_attempts['"]\)/);
  assert.match(appDb, /functions\/v1\/secure-login/);
  assert.match(secureLogin, /trustedClient\.rpc\("record_failed_login"/);
  assert.match(secureLogin, /serviceRoleKey/);
  assert.doesNotMatch(secureLogin, /console\.(?:log|info|warn|error)\s*\(/);
  assert.match(config, /\[functions\.secure-login\][\s\S]*?verify_jwt = false/);
  assert.doesNotMatch(appDb, /SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY/);
  assert.doesNotMatch(app, /SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY/);
});

test('secure login enforces lockout server-side before Auth and counts only genuine bad credentials', () => {
  assert.match(secureLogin, /from\("login_attempts"\)[\s\S]*?select\("locked_until"\)/);
  assert.match(secureLogin, /if \(lockoutError\) return serviceUnavailable\(origin\)/);
  assert.match(secureLogin, /lockout\?\.locked_until[\s\S]*?return genericFailure\(origin\)/);
  assert.ok(secureLogin.indexOf('maybeSingle()') < secureLogin.indexOf('authClient.auth.signInWithPassword'));
  assert.match(secureLogin, /error\?\.status === 400[\s\S]*?record_failed_login/);
  assert.match(secureLogin, /access_token: session\.access_token, refresh_token: session\.refresh_token/);
  assert.doesNotMatch(secureLogin, /serviceRoleKey[^\n]*JSON\.stringify/);
  assert.doesNotMatch(secureLogin, /console\.(?:log|info|warn|error)\s*\(/);
  assert.match(appDb, /auth\.setSession\(/);
  assert.doesNotMatch(appDb, /auth\.signInWithPassword\(/);
});

test('lockout reset requires an authenticated active profile and limits non-admins to self', () => {
  assert.match(migration, /actor_id uuid := auth\.uid\(\)/);
  assert.match(migration, /actor_active IS DISTINCT FROM TRUE/);
  assert.match(migration, /IF actor_role = 'ADMIN' THEN/);
  assert.match(migration, /ELSIF actor_email = requested_email THEN/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.reset_login_lockout\(text\) FROM PUBLIC, anon/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.reset_login_lockout\(text\) TO authenticated/);
  assert.match(migration, /reset_login_lockout\(user_email text\)[\s\S]*?SET search_path = pg_catalog, public, auth, pg_temp/);
  assert.match(app, /await db\.resetLoginLockout\(email\)/);
});

test('delete_user body is not replaced; only safe search path and execute grants are managed', () => {
  assert.match(migration, /ALTER FUNCTION public\.delete_user\(uuid\)\s+SET search_path = pg_catalog, public, auth, pg_temp/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.delete_user\(uuid\) FROM PUBLIC, anon/);
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.delete_user\(uuid\) TO authenticated/);
  assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION public\.delete_user/);
});

test('lockout reset and sign-out do not log raw authentication/security failures', () => {
  const resetLockout = methodBody(appDb, 'async resetLoginLockout(', 'async fetchTimePunches(');
  const signOut = methodBody(appDb, 'async signOut(', 'async sendPasswordResetEmail(');
  assert.doesNotMatch(resetLockout, /console\.(?:error|warn|log)\s*\(/);
  assert.doesNotMatch(signOut, /console\.(?:error|warn|log)\s*\(/);
  assert.doesNotMatch(signOut, /authErrorMessage\s*\(/);
  assert.match(app, /showToast\(error\?\.status === 401 \? t\('invalid_credentials'\) : t\('auth_service_unavailable'\), 'danger'\)/);
});

test('secure-login origin policy allows exact HR.sys Preview origins only', async () => {
  assert.match(secureLogin, /isAllowedSecureLoginOrigin\(origin, Deno\.env\.get\("HR_SYS_VERCEL_PREVIEW_ORIGIN"\)\)/);
  const { isAllowedSecureLoginOrigin } = await import('../supabase/functions/_shared/secure-login-origin.mjs');
  const preview = 'https://hr-sys-git-staging-slinke-hub.vercel.app';

  assert.equal(isAllowedSecureLoginOrigin('https://sys.muqam.net'), true);
  assert.equal(isAllowedSecureLoginOrigin(preview, preview), true);
  assert.equal(isAllowedSecureLoginOrigin('http://localhost:4173'), true);
  assert.equal(isAllowedSecureLoginOrigin('https://127.0.0.1:4173'), true);
  assert.equal(isAllowedSecureLoginOrigin('capacitor://localhost'), true);
  assert.equal(isAllowedSecureLoginOrigin('https://other-project-git-main-team.vercel.app'), false);
  assert.equal(isAllowedSecureLoginOrigin('https://hr-sys-git-another-branch-slinke-hub.vercel.app', preview), false);
  assert.equal(isAllowedSecureLoginOrigin('https://hr-sys-git-staging-slinke-hub.vercel.app.evil', preview), false);
  assert.equal(isAllowedSecureLoginOrigin('https://hr-sys-git-staging-slinke-hub.vercel.app/path', preview), false);
  assert.equal(isAllowedSecureLoginOrigin('javascript://hr-sys-git-staging-slinke-hub.vercel.app', preview), false);
  assert.equal(isAllowedSecureLoginOrigin('http://localhost/path'), false);
  assert.equal(isAllowedSecureLoginOrigin('not an origin', preview), false);
  assert.equal(isAllowedSecureLoginOrigin('https://other-project.vercel.app', 'https://other-project.vercel.app'), false);
  assert.equal(isAllowedSecureLoginOrigin(preview, '*'), false);
});
