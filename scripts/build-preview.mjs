import { readFile, writeFile } from 'node:fs/promises';
import { relative, resolve } from 'node:path';
import { renderRuntimeDbBundle, resolveBuildOutput } from './runtime-db-bundle.mjs';

const stagingRef = 'jcfyyxsuspukcmybyhjj';
const productionRef = 'bbbetcdioiaozdjkvwxu';
const productionOrigin = `https://${productionRef}.supabase.co`;
const stagingOrigin = `https://${stagingRef}.supabase.co`;
const projectRoot = resolve(import.meta.dirname, '..');
const outputRoot = resolveBuildOutput(projectRoot, 'www');

function readStagingAnonKey() {
  const candidates = [
    ['VERCEL_STAGING_ANON_KEY', process.env.VERCEL_STAGING_ANON_KEY],
    ['HR_SYS_STAGING_ANON_KEY', process.env.HR_SYS_STAGING_ANON_KEY],
    ['MUQAM_SUPABASE_ANON_KEY', process.env.MUQAM_SUPABASE_ANON_KEY],
  ];
  const selected = candidates.find(([, value]) => Boolean(value));
  return {
    value: String(selected?.[1] || '').trim(),
    sourceName: selected?.[0] || 'NONE',
  };
}

function keyFormat(value) {
  if (value.startsWith('sb_publishable_')) return 'sb_publishable';
  if (value.split('.').length === 3) return 'legacy-jwt';
  return 'other';
}

function logPreviewBuildDiagnostic({ sourceName, value, stagingProjectRefValid, runtimeConfigGenerated }) {
  console.log(JSON.stringify({
    diagnostic: 'preview-build-runtime-config',
    selectedEnvVariableName: sourceName,
    selectedKeyFormat: keyFormat(value),
    stagingProjectRefValid,
    runtimeConfigGenerated,
    runtimeConfigPath: relative(projectRoot, resolve(outputRoot, 'runtime-config.js')).replaceAll('\\', '/'),
  }));
}

function isStagingAnonKey(value) {
  try {
    const parts = value.split('.');
    if (parts.length !== 3) return false;
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return payload.ref === stagingRef && payload.role === 'anon';
  } catch (_) {
    return false;
  }
}

const { value: anonKey, sourceName } = readStagingAnonKey();
const stagingProjectRefValid = isStagingAnonKey(anonKey);
if (!stagingProjectRefValid) {
  logPreviewBuildDiagnostic({ sourceName, value: anonKey, stagingProjectRefValid, runtimeConfigGenerated: false });
  throw new Error('Preview build requires a valid staging public anon key; production fallback is disabled.');
}

await import('./build-mobile.mjs');
const sourceIndex = await readFile(resolve(projectRoot, 'index.html'), 'utf8');
const sourceDb = await readFile(resolve(projectRoot, 'js', 'db.js'), 'utf8');
const cspMetaPattern = /(<meta\s+http-equiv="Content-Security-Policy"\s+content=")(.*?)(">)/i;
const cspMatch = sourceIndex.match(cspMetaPattern);
if (!cspMatch) throw new Error('Content-Security-Policy meta tag was not found.');
const stagingCsp = cspMatch[2]
  .replaceAll(` ${productionOrigin}`, '')
  .replaceAll(` wss://${productionRef}.supabase.co`, '');
if (stagingCsp.includes(productionRef) || !stagingCsp.includes(stagingOrigin)) {
  throw new Error('Preview CSP failed the staging-only target check.');
}
await writeFile(resolve(outputRoot, 'index.html'), sourceIndex.replace(cspMetaPattern, `$1${stagingCsp}$3`), 'utf8');
await writeFile(resolve(outputRoot, 'js', 'db.js'), renderRuntimeDbBundle(sourceDb, 'staging'), 'utf8');
const runtimeConfig = {
  mode: 'staging',
  valid: true,
  projectRef: stagingRef,
  supabaseUrl: `https://${stagingRef}.supabase.co`,
  anonKey,
};
await writeFile(
  resolve(outputRoot, 'runtime-config.js'),
  `window.HR_RUNTIME_CONFIG=${JSON.stringify(runtimeConfig)};\n`,
  'utf8',
);

const runtimeConfigPath = resolve(outputRoot, 'runtime-config.js');
const generated = await readFile(runtimeConfigPath, 'utf8');
if (!generated.includes(stagingRef) || generated.includes('bbbetcdioiaozdjkvwxu')) {
  throw new Error('Preview runtime configuration failed the staging-only target check.');
}
const generatedIndex = await readFile(resolve(outputRoot, 'index.html'), 'utf8');
const generatedDb = await readFile(resolve(outputRoot, 'js', 'db.js'), 'utf8');
if (generatedIndex.includes(productionRef) || generatedDb.includes(productionRef) || generatedDb.includes(productionOrigin)) {
  throw new Error('Preview browser artifact contains production Supabase configuration.');
}
logPreviewBuildDiagnostic({ sourceName, value: anonKey, stagingProjectRefValid, runtimeConfigGenerated: true });
console.log(`Preview web bundle created in ${outputRoot} with a staging-only runtime configuration.`);
