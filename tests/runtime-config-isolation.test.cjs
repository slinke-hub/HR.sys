const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const { resolveHrSupabaseRuntimeConfig } = require('../js/runtime-config-resolver.js');

const root = path.resolve(__dirname, '..');
const prodRef = 'bbbetcdioiaozdjkvwxu';
const stagingRef = 'jcfyyxsuspukcmybyhjj';
const url = ref => `https://${ref}.supabase.co`;
const key = (ref, role = 'anon') => `header.${Buffer.from(JSON.stringify({ ref, role })).toString('base64url')}.signature`;
const production = { projectRef: prodRef, supabaseUrl: url(prodRef), anonKey: key(prodRef) };
const staging = { projectRef: stagingRef, supabaseUrl: url(stagingRef) };
const config = (mode, ref, anonKey) => ({ mode, valid: true, projectRef: ref, supabaseUrl: url(ref), ...(anonKey ? { anonKey } : {}) });

assert.equal(resolveHrSupabaseRuntimeConfig(config('staging', stagingRef, key(stagingRef)), { allowedModes: ['staging'], production, staging }).valid, true);
assert.equal(resolveHrSupabaseRuntimeConfig(config('staging', prodRef, key(prodRef)), { allowedModes: ['staging'], production, staging }).valid, false, 'staging may not initialize against production');
assert.equal(resolveHrSupabaseRuntimeConfig(config('production', stagingRef), { allowedModes: ['production'], production, staging }).valid, false, 'production may not initialize against staging');
assert.equal(resolveHrSupabaseRuntimeConfig(config('production', prodRef), { allowedModes: ['production'], production, staging }).valid, true);
assert.equal(resolveHrSupabaseRuntimeConfig(config('staging', stagingRef, key(stagingRef, 'service_role')), { allowedModes: ['staging'], production, staging }).valid, false, 'privileged JWT roles are rejected');
assert.equal(resolveHrSupabaseRuntimeConfig({ ...config('staging', stagingRef, key(stagingRef)), unrelated: true }, { allowedModes: ['staging'], production, staging }).valid, false, 'mixed runtime configuration is rejected');
assert.equal(resolveHrSupabaseRuntimeConfig(null, { allowedModes: ['production', 'staging'], production, staging }).valid, false, 'missing runtime configuration fails closed');
assert.equal(resolveHrSupabaseRuntimeConfig(config('unknown', stagingRef, key(stagingRef)), { allowedModes: ['production', 'staging'], production, staging }).valid, false, 'unknown runtime mode fails closed');

const sourceDb = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
const resolverSource = fs.readFileSync(path.join(root, 'js/runtime-config-resolver.js'), 'utf8');
const marker = 'const SUPABASE_REQUEST_TIMEOUT_MS = 10000;';
function evaluateGeneratedClient(dbBundle, runtimeConfig) {
  const windowObject = { atob: value => Buffer.from(value, 'base64').toString('binary'), HR_RUNTIME_CONFIG: runtimeConfig };
  const context = vm.createContext({ window: windowObject });
  vm.runInContext(resolverSource, context, { timeout: 1000 });
  const bodyIndex = dbBundle.indexOf(marker);
  assert.ok(bodyIndex > 0, 'generated client includes the original client logic');
  vm.runInContext(dbBundle.slice(0, bodyIndex), context, { timeout: 1000 });
  return windowObject;
}

const temporaryRoot = fs.mkdtempSync(path.join(root, 'node_modules', '.hrsys-phase1-artifacts-'));
const previewOutput = path.join(temporaryRoot, 'preview');
const productionOutput = path.join(temporaryRoot, 'production');
const relative = output => path.relative(root, output);
const fakeStagingKey = key(stagingRef);
function runBuild(script, output, extraEnv = {}) {
  return spawnSync(process.execPath, [path.join(root, 'scripts', script)], {
    cwd: root,
    encoding: 'utf8',
    env: { ...process.env, HR_SYS_BUILD_OUTPUT: relative(output), ...extraEnv },
    timeout: 120000,
  });
}
function artifactFiles(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...artifactFiles(entryPath));
    else files.push(entryPath);
  }
  return files;
}

try {
  const preview = runBuild('build-preview.mjs', previewOutput, { HR_SYS_STAGING_ANON_KEY: fakeStagingKey });
  assert.equal(preview.status, 0, `Preview artifact build failed: ${preview.stderr || preview.stdout}`);
  const productionBuild = runBuild('build-production.mjs', productionOutput);
  assert.equal(productionBuild.status, 0, `Production artifact build failed: ${productionBuild.stderr || productionBuild.stdout}`);

  const previewFiles = artifactFiles(previewOutput);
  const productionFiles = artifactFiles(productionOutput);
  const previewText = previewFiles.map(file => fs.readFileSync(file, 'utf8')).join('\n');
  const productionText = productionFiles.map(file => fs.readFileSync(file, 'utf8')).join('\n');
  assert.ok(fs.existsSync(path.join(previewOutput, 'css', 'task-manager-mobile-final.css')));
  assert.ok(fs.existsSync(path.join(productionOutput, 'css', 'task-manager-mobile-final.css')));
  assert.ok(previewText.includes(stagingRef));
  assert.ok(!previewText.includes(prodRef), 'Preview browser artifact is staging-only');
  assert.ok(productionText.includes(prodRef));
  assert.ok(!productionText.includes(stagingRef), 'Production browser artifact is production-only');
  assert.match(fs.readFileSync(path.join(previewOutput, 'index.html'), 'utf8'), new RegExp(stagingRef));
  assert.doesNotMatch(fs.readFileSync(path.join(previewOutput, 'index.html'), 'utf8'), new RegExp(prodRef));
  assert.doesNotMatch(fs.readFileSync(path.join(productionOutput, 'index.html'), 'utf8'), new RegExp(stagingRef));
  for (const text of [previewText, productionText]) {
    assert.doesNotMatch(text, /SUPABASE_SERVICE_ROLE_KEY|service_role.{0,80}eyJ|PRIVATE_VAPID_KEY|PUSH_DISPATCH_SECRET|DATABASE_PASSWORD/i);
  }

  const previewDb = fs.readFileSync(path.join(previewOutput, 'js', 'db.js'), 'utf8');
  const productionDb = fs.readFileSync(path.join(productionOutput, 'js', 'db.js'), 'utf8');
  assert.equal(evaluateGeneratedClient(previewDb, config('staging', stagingRef, fakeStagingKey)).hrRuntimeConfigError, null);
  assert.notEqual(evaluateGeneratedClient(previewDb, config('production', prodRef)).hrRuntimeConfigError, null, 'Preview artifact rejects production runtime config');
  assert.notEqual(evaluateGeneratedClient(previewDb, null).hrRuntimeConfigError, null, 'Preview artifact rejects missing config');
  assert.notEqual(evaluateGeneratedClient(previewDb, config('unknown', stagingRef, fakeStagingKey)).hrRuntimeConfigError, null, 'Preview artifact rejects unknown mode');
  assert.equal(evaluateGeneratedClient(productionDb, config('production', prodRef)).hrRuntimeConfigError, null);
  assert.notEqual(evaluateGeneratedClient(productionDb, config('staging', stagingRef, fakeStagingKey)).hrRuntimeConfigError, null, 'Production artifact rejects staging runtime config');
  assert.notEqual(evaluateGeneratedClient(productionDb, null).hrRuntimeConfigError, null, 'Production artifact rejects missing config');

  const missingPreviewKey = runBuild('build-preview.mjs', path.join(temporaryRoot, 'missing-key'), {
    VERCEL_STAGING_ANON_KEY: '', HR_SYS_STAGING_ANON_KEY: '', MUQAM_SUPABASE_ANON_KEY: '',
  });
  assert.notEqual(missingPreviewKey.status, 0, 'Preview build fails closed without staging public key');
  assert.match(missingPreviewKey.stderr, /requires a valid staging public anon key/);

  const dbBeforeUnsafeOutput = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
  const unsafeOutput = runBuild('build-preview.mjs', path.join(root, 'js'));
  assert.notEqual(unsafeOutput.status, 0, 'custom build output may not target source files');
  assert.match(unsafeOutput.stderr, /Custom build output is restricted/);
  assert.equal(fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8'), dbBeforeUnsafeOutput, 'unsafe output request does not touch source files');

  const helperPath = path.join(root, 'scripts', 'runtime-db-bundle.mjs');
  const helper = spawnSync(process.execPath, ['--input-type=module', '-e', `import { readFile } from 'node:fs/promises'; import { renderRuntimeDbBundle } from ${JSON.stringify(pathToFileURL(helperPath).href)}; const db=await readFile(new URL(${JSON.stringify(pathToFileURL(path.join(root, 'js/db.js')).href)}),'utf8'); process.stdout.write(renderRuntimeDbBundle(db,'unknown'));`], { cwd: root, encoding: 'utf8', timeout: 10000 });
  assert.equal(helper.status, 0, `Unknown-mode runtime bundle could not be generated: ${helper.stderr}`);
  assert.notEqual(evaluateGeneratedClient(helper.stdout, config('staging', stagingRef, fakeStagingKey)).hrRuntimeConfigError, null, 'unknown build mode fails closed');

  const dbSource = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
  const server = fs.readFileSync(path.join(root, 'scripts/serve-local.mjs'), 'utf8');
  assert.match(dbSource, /hrResolveSupabaseRuntimeConfig\(runtimeConfig/);
  assert.match(server, /const mode = String\(process\.env\.HR_SYS_RUNTIME \|\| ''\)\.trim\(\)/);
  assert.match(server, /Explicit local runtime environment is required/);
  assert.match(server, /renderRuntimeDbBundle\(sourceDb, targetMode\)/);
  console.log('Runtime isolation tests passed, including real Preview/Production artifacts and fail-closed mode checks.');
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
