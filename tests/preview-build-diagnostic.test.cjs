const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const stagingRef = 'jcfyyxsuspukcmybyhjj';
const key = (ref, role = 'anon') => (
  `header.${Buffer.from(JSON.stringify({ ref, role })).toString('base64url')}.signature`
);
const fakeStagingKey = key(stagingRef);
const temporaryRoot = fs.mkdtempSync(path.join(root, 'node_modules', '.hrsys-phase1-artifacts-preview-diagnostic-'));
const relative = output => path.relative(root, output);

function runPreviewBuild(output, extraEnv = {}) {
  return spawnSync(process.execPath, [path.join(root, 'scripts', 'build-preview.mjs')], {
    cwd: root,
    encoding: 'utf8',
    env: {
      ...process.env,
      VERCEL_STAGING_ANON_KEY: '',
      HR_SYS_STAGING_ANON_KEY: '',
      MUQAM_SUPABASE_ANON_KEY: '',
      HR_SYS_BUILD_OUTPUT: relative(output),
      ...extraEnv,
    },
    timeout: 120000,
  });
}

try {
  const previewOutput = path.join(temporaryRoot, 'preview');
  const preview = runPreviewBuild(previewOutput, { HR_SYS_STAGING_ANON_KEY: fakeStagingKey });
  assert.equal(preview.status, 0, 'Preview diagnostic build succeeds with a valid staging key');
  assert.match(preview.stdout, /"selectedEnvVariableName":"HR_SYS_STAGING_ANON_KEY"/);
  assert.match(preview.stdout, /"selectedKeyFormat":"legacy-jwt"/);
  assert.match(preview.stdout, /"stagingProjectRefValid":true/);
  assert.match(preview.stdout, /"runtimeConfigGenerated":true/);
  assert.match(
    preview.stdout,
    /"runtimeConfigPath":"node_modules\/\.hrsys-phase1-artifacts-preview-diagnostic-[A-Za-z0-9-]+\/preview\/runtime-config\.js"/,
  );
  assert.doesNotMatch(
    `${preview.stdout}\n${preview.stderr}`,
    new RegExp(fakeStagingKey.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'build diagnostic never prints the selected key',
  );

  const missingOutput = path.join(temporaryRoot, 'missing-key');
  const missing = runPreviewBuild(missingOutput);
  assert.notEqual(missing.status, 0, 'Preview build fails closed without a staging key');
  assert.match(missing.stderr, /requires a valid staging public anon key/);
  assert.match(missing.stdout, /"selectedEnvVariableName":"NONE"/);
  assert.match(missing.stdout, /"selectedKeyFormat":"other"/);
  assert.match(missing.stdout, /"stagingProjectRefValid":false/);
  assert.match(missing.stdout, /"runtimeConfigGenerated":false/);
  assert.doesNotMatch(
    `${missing.stdout}\n${missing.stderr}`,
    /VERCEL_STAGING_ANON_KEY|HR_SYS_STAGING_ANON_KEY|MUQAM_SUPABASE_ANON_KEY/,
    'missing-key diagnostic does not expose credential values or environment contents',
  );

  console.log('Preview build diagnostic tests passed.');
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
