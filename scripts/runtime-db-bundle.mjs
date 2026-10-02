import { relative, resolve, sep } from 'node:path';

const PRODUCTION_REF = 'bbbetcdioiaozdjkvwxu';
const STAGING_REF = 'jcfyyxsuspukcmybyhjj';
const PRODUCTION_ORIGIN = `https://${PRODUCTION_REF}.supabase.co`;
const STAGING_ORIGIN = `https://${STAGING_REF}.supabase.co`;
const DB_BODY_MARKER = 'const SUPABASE_REQUEST_TIMEOUT_MS = 10000;';

function jwtPayload(value) {
  const parts = String(value || '').split('.');
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch (_) {
    return null;
  }
}

export function resolveBuildOutput(projectRoot, defaultName) {
  if (!['www', 'www-production'].includes(defaultName)) {
    throw new Error('Unrecognized generated build output directory.');
  }
  const configured = process.env.HR_SYS_BUILD_OUTPUT || defaultName;
  const outputRoot = resolve(projectRoot, configured);
  const normalizedRoot = resolve(projectRoot, '.');
  const relativeOutput = relative(normalizedRoot, outputRoot);
  if (!relativeOutput || relativeOutput === '..' || relativeOutput.startsWith(`..${sep}`) || resolve(normalizedRoot, relativeOutput) !== outputRoot) {
    throw new Error('Refusing to write a build output outside the project directory.');
  }
  if (process.env.HR_SYS_BUILD_OUTPUT) {
    const [nodeModules, testRoot] = relativeOutput.split(sep);
    if (nodeModules !== 'node_modules' || !/^\.hrsys-phase1-artifacts-[A-Za-z0-9-]+$/.test(testRoot || '')) {
      throw new Error('Custom build output is restricted to isolated Phase 1 test-artifact directories under node_modules.');
    }
  }
  return outputRoot;
}

export function renderRuntimeDbBundle(sourceDb, mode) {
  const markerIndex = sourceDb.indexOf(DB_BODY_MARKER);
  if (markerIndex < 0) throw new Error('Database client logic marker was not found.');
  const productionKeyMatch = sourceDb.match(/const PRODUCTION_SUPABASE_ANON_KEY = '([^']+)'/);
  const productionAnonKey = productionKeyMatch?.[1] || '';
  const productionPayload = jwtPayload(productionAnonKey);

  let allowedModes = [];
  let targetConfig = '';
  let label = 'unconfigured';
  if (mode === 'production') {
    if (productionPayload?.ref !== PRODUCTION_REF || productionPayload?.role !== 'anon') {
      throw new Error('Production public Supabase configuration is invalid.');
    }
    allowedModes = ['production'];
    label = 'production';
    targetConfig = `production: { projectRef: '${PRODUCTION_REF}', supabaseUrl: '${PRODUCTION_ORIGIN}', anonKey: '${productionAnonKey}' }`;
  } else if (mode === 'staging') {
    allowedModes = ['staging'];
    label = 'staging';
    targetConfig = `staging: { projectRef: '${STAGING_REF}', supabaseUrl: '${STAGING_ORIGIN}' }`;
  }

  const prefix = `/* eslint-disable no-redeclare, no-global-assign */\n/* exported db */\n// Environment-bound runtime configuration generated for ${label}.\nconst injectedRuntimeConfig = window.HR_RUNTIME_CONFIG;\nconst runtimeResolution = typeof window.hrResolveSupabaseRuntimeConfig === 'function'\n  ? window.hrResolveSupabaseRuntimeConfig(injectedRuntimeConfig, { allowedModes: ${JSON.stringify(allowedModes)}, ${targetConfig} })\n  : { valid: false, mode: null, supabaseUrl: null, anonKey: null, error: 'Runtime configuration validator is unavailable.' };\nif (!runtimeResolution.valid) {\n  window.hrRuntimeMode = '${label}';\n  window.hrRuntimeConfigError = runtimeResolution.error;\n} else {\n  window.hrRuntimeMode = runtimeResolution.mode;\n  window.hrRuntimeConfigError = null;\n}\nconst runtimeMode = runtimeResolution.mode;\nconst SUPABASE_URL = runtimeResolution.valid ? runtimeResolution.supabaseUrl : null;\nconst SUPABASE_ANON_KEY = runtimeResolution.valid ? runtimeResolution.anonKey : null;\n`;
  return `${prefix}\n${sourceDb.slice(markerIndex)}`;
}
