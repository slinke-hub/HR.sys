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

const dbSource = read('js/db.js');
assert.match(dbSource, /function createStorageReference\(/);
assert.match(dbSource, /createSignedUrl\(/);
assert.doesNotMatch(dbSource, /\.from\('(?:task-attachments|contract-documents|crm-deal-files)'\)\.getPublicUrl/);

const html = read('index.html');
assert.match(html, /Content-Security-Policy/);
assert.match(html, /object-src 'none'/);
assert.match(html, /base-uri 'self'/);

const vercel = JSON.parse(read('vercel.json'));
assert.strictEqual(vercel.outputDirectory, 'www');
assert.match(vercel.buildCommand, /mobile:web/);
const globalHeaders = vercel.headers.find(entry => entry.source === '/(.*)').headers;
const headerMap = Object.fromEntries(globalHeaders.map(header => [header.key, header.value]));
assert.strictEqual(headerMap['X-Content-Type-Options'], 'nosniff');
assert.strictEqual(headerMap['X-Frame-Options'], 'DENY');
assert.match(headerMap['Content-Security-Policy'], /frame-ancestors 'none'/);

const migration = read('supabase/migrations/20260910123000_revoke_anonymous_security_definer_execution.sql');
assert.match(migration, /REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon/);
assert.match(migration, /procedure\.prosecdef/);

const storageMigration = read('supabase/migrations/20260910123500_private_sensitive_storage.sql');
assert.match(storageMigration, /SET public = false/);
assert.match(storageMigration, /sensitive_contract_documents_read/);
assert.match(storageMigration, /sensitive_task_attachments_read/);

console.log('Security hardening regression checks passed.');
