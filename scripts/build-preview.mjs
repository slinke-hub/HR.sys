import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const stagingRef = 'jcfyyxsuspukcmybyhjj';
const projectRoot = resolve(import.meta.dirname, '..');
const outputRoot = resolve(projectRoot, 'www');

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
console.log('Preview web bundle created in www/ with a staging-only runtime configuration.');
