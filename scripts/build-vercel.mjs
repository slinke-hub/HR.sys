import { cp, mkdir, readdir, readFile, rm } from 'node:fs/promises';
import { dirname, relative, resolve, sep } from 'node:path';
import { spawnSync } from 'node:child_process';

const projectRoot = resolve(import.meta.dirname, '..');
const outputRoot = resolve(projectRoot, 'www-vercel');
const productionRoot = resolve(projectRoot, 'www-production');
const previewRoot = resolve(projectRoot, 'www');
const productionRef = 'bbbetcdioiaozdjkvwxu';
const stagingRef = 'jcfyyxsuspukcmybyhjj';
const productionOrigin = `https://${productionRef}.supabase.co`;
const stagingOrigin = `https://${stagingRef}.supabase.co`;
const outputPrefix = `${projectRoot}${sep}`;

function assertSafeGeneratedPath(path, label) {
  if (!path.startsWith(outputPrefix) || path === projectRoot) {
    throw new Error(`Refusing to modify an unsafe ${label} path.`);
  }
}

function readDeploymentEnvironment() {
  const target = String(process.env.VERCEL_TARGET_ENV || '').trim().toLowerCase();
  const environment = String(process.env.VERCEL_ENV || '').trim().toLowerCase();
  const selected = target || environment;
  if (selected === 'production' || selected === 'preview') return selected;
  throw new Error('Vercel deployment environment is missing or unsupported; refusing to choose a build target.');
}

function readPreviewKey() {
  return String(
    process.env.VERCEL_STAGING_ANON_KEY
      || process.env.HR_SYS_STAGING_ANON_KEY
      || process.env.MUQAM_SUPABASE_ANON_KEY
      || '',
  ).trim();
}

function assertNoPrivilegedPreviewKey(value) {
  if (!value || /service[_-]?role|sb_secret_|private[_-]?vapid|push[_-]?dispatch|database[_-]?password/i.test(value)) {
    throw new Error('Preview requires a staging public anon/publishable key; privileged or missing credentials are rejected.');
  }
}

async function listFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const path = resolve(root, entry.name);
    if (entry.isDirectory()) files.push(...await listFiles(path));
    else files.push(path);
  }
  return files;
}

async function readTextFiles(root) {
  const files = await listFiles(root);
  const textExtensions = new Set(['.css', '.html', '.js', '.json', '.mjs', '.txt', '.webmanifest']);
  const texts = [];
  for (const file of files) {
    if (textExtensions.has(file.slice(file.lastIndexOf('.')).toLowerCase())) {
      texts.push(await readFile(file, 'utf8'));
    }
  }
  return texts.join('\n');
}

function runBuilder(builder) {
  const result = spawnSync(process.execPath, [resolve(projectRoot, builder)], {
    cwd: projectRoot,
    env: process.env,
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${builder} failed with exit code ${result.status}.`);
}

async function copySelectedBuild(sourceRoot) {
  assertSafeGeneratedPath(outputRoot, 'Vercel output');
  await rm(outputRoot, { recursive: true, force: true });
  await mkdir(outputRoot, { recursive: true });
  await cp(sourceRoot, outputRoot, { recursive: true, force: true });
}

function assertNoPrivilegedSecretValues(text) {
  const credentialPatterns = [
    /-----BEGIN (?:RSA|OPENSSH|EC|PRIVATE) KEY-----/i,
    /postgres(?:ql)?:\/\/[^\s"']+:[^\s"']+@/i,
    /sb_secret_[A-Za-z0-9]{20,}/,
    /(?:service[_-]?role|SUPABASE_SERVICE_ROLE_KEY|VAPID_PRIVATE_KEY|PUSH_DISPATCH_SECRET)\s*[:=]\s*['"][^'"]+['"]/i,
  ];
  if (credentialPatterns.some(pattern => pattern.test(text))) {
    throw new Error('Generated browser output contains a privileged credential-shaped value.');
  }
}

async function verifyOutput(environment) {
  const files = await listFiles(outputRoot);
  const relativeFiles = files.map(file => relative(outputRoot, file).replaceAll('\\', '/'));
  const text = await readTextFiles(outputRoot);
  if (!relativeFiles.some(file => file.endsWith('task-manager-mobile-final.css'))) {
    throw new Error('Generated Vercel output is missing task-manager-mobile-final.css.');
  }
  assertNoPrivilegedSecretValues(text);

  if (environment === 'production') {
    if (!text.includes(productionRef) || !text.includes(productionOrigin)) {
      throw new Error('Production Vercel output is missing the production Supabase target.');
    }
    if (text.includes(stagingRef) || text.includes(stagingOrigin)) {
      throw new Error('Production Vercel output contains the staging Supabase target.');
    }
  } else {
    const runtimeConfig = await readFile(resolve(outputRoot, 'runtime-config.js'), 'utf8');
    if (!runtimeConfig.includes(stagingRef) || runtimeConfig.includes(productionRef)) {
      throw new Error('Preview Vercel output is not staging-only.');
    }
  }
}

const environment = readDeploymentEnvironment();
if (environment === 'preview') {
  assertNoPrivilegedPreviewKey(readPreviewKey());
}

const builder = environment === 'production'
  ? 'scripts/build-production.mjs'
  : 'scripts/build-preview.mjs';
const sourceRoot = environment === 'production' ? productionRoot : previewRoot;
runBuilder(builder);
await copySelectedBuild(sourceRoot);
await verifyOutput(environment);
console.log(`Vercel ${environment} bundle created in ${outputRoot}.`);
