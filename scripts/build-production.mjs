import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const projectRoot = resolve(import.meta.dirname, '..');
const outputRoot = resolve(projectRoot, 'www-production');
const productionRef = 'bbbetcdioiaozdjkvwxu';
const stagingRef = 'jcfyyxsuspukcmybyhjj';
const productionOrigin = `https://${productionRef}.supabase.co`;
const stagingOrigin = `https://${stagingRef}.supabase.co`;
const assetDirectories = ['css', 'images', 'js', 'templates'];
const rootFiles = ['index.html', 'manifest.json', 'offline.html', 'sw.js'];

if (!outputRoot.startsWith(`${projectRoot}\\`) && !outputRoot.startsWith(`${projectRoot}/`)) {
  throw new Error('Refusing to clean a production output directory outside the project.');
}

const sourceIndex = await readFile(resolve(projectRoot, 'index.html'), 'utf8');
const sourceDb = await readFile(resolve(projectRoot, 'js', 'db.js'), 'utf8');

const anonKeyMatch = sourceDb.match(/const PRODUCTION_SUPABASE_ANON_KEY = '([^']+)'/);
if (!anonKeyMatch) throw new Error('Production public Supabase anon key is missing from the source configuration.');
const productionAnonKey = anonKeyMatch[1];
const jwtParts = productionAnonKey.split('.');
if (jwtParts.length !== 3) throw new Error('Production Supabase public key is not a JWT.');
let jwtPayload;
try {
  jwtPayload = JSON.parse(Buffer.from(jwtParts[1], 'base64url').toString('utf8'));
} catch {
  throw new Error('Production Supabase public key payload could not be parsed.');
}
if (jwtPayload.ref !== productionRef || jwtPayload.role !== 'anon') {
  throw new Error('Production public key does not belong to the expected production project or anon role.');
}

const cspMetaPattern = /(<meta\s+http-equiv="Content-Security-Policy"\s+content=")(.*?)(">)/i;
const cspMatch = sourceIndex.match(cspMetaPattern);
if (!cspMatch) throw new Error('Content-Security-Policy meta tag was not found.');
const productionCsp = cspMatch[2]
  .replaceAll(` ${stagingOrigin}`, '')
  .replaceAll(` wss://${stagingRef}.supabase.co`, '');
if (productionCsp.includes(stagingRef)) throw new Error('Staging project reference remains in the production CSP.');
if (!productionCsp.includes(productionOrigin)) throw new Error('Production Supabase origin is missing from the production CSP.');
const productionIndex = sourceIndex
  .replace(cspMetaPattern, `$1${productionCsp}$3`)
  .replace(/\s*<script\s+defer\s+src="runtime-config\.js"><\/script>\s*/gi, '\n');

const dbMarker = 'const SUPABASE_REQUEST_TIMEOUT_MS = 10000;';
const dbMarkerIndex = sourceDb.indexOf(dbMarker);
if (dbMarkerIndex < 0) throw new Error('Database client logic marker was not found.');
const productionDbPrefix = `/* eslint-disable no-redeclare, no-global-assign */\n/* exported db */\n// This file is generated for the explicit production browser build.\nconst PRODUCTION_PROJECT_REF = '${productionRef}';\nconst PRODUCTION_SUPABASE_URL = '${productionOrigin}';\nconst PRODUCTION_SUPABASE_ANON_KEY = '${productionAnonKey}';\nconst injectedRuntimeConfig = window.HR_RUNTIME_CONFIG;\nconst productionRuntimeValid = !injectedRuntimeConfig || (\n  String(injectedRuntimeConfig.mode || 'production').toLowerCase() === 'production'\n  && injectedRuntimeConfig.valid === true\n  && injectedRuntimeConfig.projectRef === PRODUCTION_PROJECT_REF\n  && injectedRuntimeConfig.supabaseUrl === PRODUCTION_SUPABASE_URL\n);\nif (!productionRuntimeValid) {\n  window.hrRuntimeMode = 'production';\n  window.hrRuntimeConfigError = 'Production runtime configuration mismatch.';\n  throw new Error(window.hrRuntimeConfigError);\n}\nconst SUPABASE_URL = PRODUCTION_SUPABASE_URL;\nconst SUPABASE_ANON_KEY = PRODUCTION_SUPABASE_ANON_KEY;\nconst runtimeMode = 'production';\nwindow.hrRuntimeMode = runtimeMode;\nwindow.hrRuntimeConfigError = null;\n`;
const productionDb = `${productionDbPrefix}\n${sourceDb.slice(dbMarkerIndex)}`;

await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });
for (const directory of assetDirectories) {
  await cp(resolve(projectRoot, directory), resolve(outputRoot, directory), { recursive: true });
}
for (const file of rootFiles) {
  await cp(resolve(projectRoot, file), resolve(outputRoot, file));
}
await writeFile(resolve(outputRoot, 'index.html'), productionIndex, 'utf8');
await writeFile(resolve(outputRoot, 'js', 'db.js'), productionDb, 'utf8');

const verifyIndex = await readFile(resolve(outputRoot, 'index.html'), 'utf8');
const verifyDb = await readFile(resolve(outputRoot, 'js', 'db.js'), 'utf8');
if (verifyIndex.includes(stagingRef) || verifyDb.includes(stagingRef)) {
  throw new Error('Production browser configuration still contains the staging project reference.');
}
if (!verifyIndex.includes(productionOrigin) || !verifyDb.includes(productionRef)) {
  throw new Error('Production browser configuration is missing the production Supabase target.');
}

console.log(`Production web bundle created in ${outputRoot}.`);
console.log(`Production Supabase project: ${productionRef}`);
