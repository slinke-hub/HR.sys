import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { renderRuntimeDbBundle, resolveBuildOutput } from './runtime-db-bundle.mjs';

const stagingRef = 'jcfyyxsuspukcmybyhjj';
const productionRef = 'bbbetcdioiaozdjkvwxu';
const productionOrigin = `https://${productionRef}.supabase.co`;
const stagingOrigin = `https://${stagingRef}.supabase.co`;
const projectRoot = resolve(import.meta.dirname, '..');
const outputRoot = resolveBuildOutput(projectRoot, 'www');

function readStagingAnonKey() {
  return String(
    process.env.VERCEL_STAGING_ANON_KEY
      || process.env.HR_SYS_STAGING_ANON_KEY
      || process.env.MUQAM_SUPABASE_ANON_KEY
      || '',
  ).trim();
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

const anonKey = readStagingAnonKey();
if (!isStagingAnonKey(anonKey)) {
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

const generated = await readFile(resolve(outputRoot, 'runtime-config.js'), 'utf8');
if (!generated.includes(stagingRef) || generated.includes('bbbetcdioiaozdjkvwxu')) {
  throw new Error('Preview runtime configuration failed the staging-only target check.');
}
const generatedIndex = await readFile(resolve(outputRoot, 'index.html'), 'utf8');
const generatedDb = await readFile(resolve(outputRoot, 'js', 'db.js'), 'utf8');
if (generatedIndex.includes(productionRef) || generatedDb.includes(productionRef) || generatedDb.includes(productionOrigin)) {
  throw new Error('Preview browser artifact contains production Supabase configuration.');
}
console.log(`Preview web bundle created in ${outputRoot} with a staging-only runtime configuration.`);
