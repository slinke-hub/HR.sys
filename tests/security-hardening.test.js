const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const read = relativePath => fs.readFileSync(path.join(root, relativePath), 'utf8');

const packageJson = JSON.parse(read('package.json'));
assert.match(packageJson.scripts.dev, /mobile:web/);
assert.match(packageJson.scripts.dev, /scripts\/serve-local\.mjs/);
assert.ok(!packageJson.devDependencies.serve);

const localServer = read('scripts/serve-local.mjs');
assert.match(localServer, /const host = '127\.0\.0\.1'/);
assert.match(localServer, /pathname\.split\('\/'\)\.some\(segment => segment\.startsWith\('\.'\)\)/);
assert.match(localServer, /X-Content-Type-Options/);

for (const helper of ['create_admin.js', 'test_create_user.js']) {
    const source = read(helper);
    assert.doesNotMatch(source, /password\s*:\s*['"][^'"]+['"]/i);
    assert.match(source, /process\.env\.MUQAM_/);
}

const appSource = read('js/app.js');
assert.match(appSource, /function safeExternalUrl\(/);
assert.match(appSource, /safeDisplayMessage/);
assert.match(appSource, /rel="noopener noreferrer"/);
assert.doesNotMatch(appSource, /Default123!/);
assert.match(appSource, /password\.length < 12/);

const dbSource = read('js/db.js');
assert.match(dbSource, /function createStorageReference\(/);
assert.match(dbSource, /functions\.invoke\('file-signed-url'/);
assert.doesNotMatch(dbSource, /storage\s*\.from\([^)]*\)\.createSignedUrl/);
assert.doesNotMatch(dbSource, /\.from\('(?:task-attachments|contract-documents|crm-deal-files)'\)\.getPublicUrl/);

const html = read('index.html');
assert.match(html, /Content-Security-Policy/);
assert.match(html, /object-src 'none'/);
assert.match(html, /base-uri 'self'/);

const vercel = read('vercel.mjs');
const vercelBuild = read('scripts/build-vercel.mjs');
assert.match(vercel, /buildCommand: 'node scripts\/build-vercel\.mjs'/);
assert.match(vercel, /outputDirectory: 'www-vercel'/);
assert.doesNotMatch(vercel, /isProduction/);
assert.match(vercelBuild, /VERCEL_TARGET_ENV/);
assert.match(vercelBuild, /VERCEL_ENV/);
assert.match(vercelBuild, /refusing to choose a build target/);
assert.match(vercelBuild, /www-vercel/);
assert.match(vercel, /frame-ancestors 'none'/);
assert.match(vercel, /upgrade-insecure-requests/);
assert.match(vercel, /X-Content-Type-Options/);
assert.match(vercel, /X-Frame-Options/);
assert.match(vercel, /max-age=63072000/);

const androidManifest = read('android/app/src/main/AndroidManifest.xml');
assert.match(androidManifest, /android:allowBackup="false"/);
assert.match(androidManifest, /android:usesCleartextTraffic="false"/);

const emailDispatcher = read('supabase/functions/task-notification-email/index.js');
assert.doesNotMatch(emailDispatcher, /"Access-Control-Allow-Origin": "\*"/);
assert.match(emailDispatcher, /TASK_EMAIL_DISPATCH_SECRET/);
assert.match(emailDispatcher, /notificationMap\.get\(item\.notification_id\)\?\.actor_id === authData\.user\.id/);

const pushDispatcher = read('supabase/functions/push-notification-dispatcher/index.ts');
assert.match(pushDispatcher, /PUSH_DISPATCH_SECRET/);
assert.match(pushDispatcher, /if \(!canDispatch\).*403/);

const supabaseConfig = read('supabase/config.toml');
assert.match(supabaseConfig, /\[functions\.push-notification-dispatcher\][\s\S]*?verify_jwt = false/);

const gitignore = read('.gitignore');
assert.match(gitignore, /\*\.keystore/);
assert.match(gitignore, /scratch\//);

const migration = read('supabase/migrations/20260910123000_revoke_anonymous_security_definer_execution.sql');
assert.match(migration, /REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon/);
assert.match(migration, /procedure\.prosecdef/);

const storageMigration = read('supabase/migrations/20260910123500_private_sensitive_storage.sql');
assert.match(storageMigration, /SET public = false/);
assert.match(storageMigration, /sensitive_contract_documents_read/);
assert.match(storageMigration, /sensitive_task_attachments_read/);

console.log('Security hardening regression checks passed.');
