/* Disposable PostgreSQL 17.6 Docker helper. No host port or network. */
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const path = require('node:path');

const IMAGE = 'postgres:17.6';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

const docker = (args, options = {}) => cp.spawnSync('docker', args, {
  encoding: 'utf8', windowsHide: true, maxBuffer: 8 * 1024 * 1024, ...options
});

function psqlArgsInContainer(args, container) {
  const translated = [...args];
  for (let i = 0; i < translated.length;) {
    if (translated[i] === '-h' || translated[i] === '-p') translated.splice(i, 2);
    else if (translated[i] === '-f') {
      const hostFile = translated[i + 1];
      const inContainer = `/tmp/hrsys-${crypto.randomBytes(8).toString('hex')}-${path.basename(hostFile)}`;
      const copied = docker(['cp', hostFile, `${container}:${inContainer}`]);
      if (copied.error) throw copied.error;
      if (copied.status !== 0) throw new Error(`Could not copy synthetic SQL into disposable container:\n${copied.stderr || copied.stdout}`);
      translated.splice(i + 1, 1, inContainer);
      i += 2;
    } else i += 1;
  }
  return translated;
}

async function start(prefix) {
  const name = `${prefix}-${process.pid}-${crypto.randomBytes(5).toString('hex')}`;
  const password = crypto.randomBytes(24).toString('hex');
  const created = docker(['run', '--detach', '--name', name, '--network', 'none',
    '--tmpfs', '/var/lib/postgresql/data:rw,noexec,nosuid,size=1g',
    '--env', `POSTGRES_PASSWORD=${password}`, IMAGE]);
  if (created.error) throw created.error;
  if (created.status !== 0) throw new Error(`Could not create isolated ${IMAGE} container:\n${created.stderr || created.stdout}`);

  try {
    let ready = false;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      const result = docker(['exec', name, 'pg_isready', '-U', 'postgres']);
      if (result.status === 0) { ready = true; break; }
      await sleep(250);
    }
    assert.ok(ready, `${IMAGE} did not become ready in its no-network container.`);
    const version = run('postgres', ['--version'], name).trim();
    assert.match(version, /PostgreSQL\)?\s+17\.6\b/i, `Expected PostgreSQL 17.6, received: ${version}`);
    return { name, version };
  } catch (error) {
    stop(name);
    throw error;
  }
}

function run(tool, args, container) {
  const normalizedTool = path.basename(tool).replace(/\.exe$/i, '').toLowerCase();
  if (normalizedTool === 'psql') {
    const translated = psqlArgsInContainer(args, container);
    const result = docker(['exec', '-i', container, 'psql', ...translated]);
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`psql failed (${result.status}):\n${result.stdout || ''}\n${result.stderr || ''}`);
    return result.stdout || '';
  }
  if (normalizedTool === 'pg_isready') {
    const result = docker(['exec', container, 'pg_isready', '-U', 'postgres']);
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`pg_isready failed: ${result.stderr || result.stdout}`);
    return result.stdout || '';
  }
  if (normalizedTool === 'postgres') {
    const result = docker(['exec', container, 'postgres', ...args]);
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`postgres failed: ${result.stderr || result.stdout}`);
    return result.stdout || '';
  }
  throw new Error(`Unsupported PostgreSQL Docker test tool: ${normalizedTool}`);
}

function spawnPsql(container, args) {
  return cp.spawn('docker', ['exec', '-i', container, 'psql', ...psqlArgsInContainer(args, container)], {
    windowsHide: true, stdio: ['ignore', 'pipe', 'pipe']
  });
}

function stop(container) {
  if (!container) return;
  const result = docker(['rm', '--force', '--volumes', container]);
  if (result.error || result.status !== 0) {
    console.error(`Could not remove test-created container ${container}: ${result.stderr || result.error || result.stdout}`);
  }
}

module.exports = { start, run, spawnPsql, stop, image: IMAGE };
