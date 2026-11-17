const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const EXPECTED_URL = 'https://github.com/advisories/GHSA-fc5q-39xc-vjpf';
const EXPECTED_PATHS = ['node_modules/picomatch', 'node_modules/tinyglobby/node_modules/picomatch'];

function evaluate(audit, policy, lock, latest, now = Date.now()) {
  if (!policy || policy.advisory !== 'GHSA-fc5q-39xc-vjpf' || policy.npmAdvisoryId !== 1247710 || policy.package !== 'picomatch'
    || policy.owner !== 'HR.sys release/security owner' || policy.latestUnpatchedVersion !== '4.0.7'
    || policy.expiresAt !== '2026-11-24T00:00:00Z' || now >= Date.parse(policy.expiresAt)
    || JSON.stringify(policy.allowedVersions) !== JSON.stringify(['2.3.2', '4.0.7'])) throw Error('Invalid or expired security exception');
  if (latest !== policy.latestUnpatchedVersion) throw Error('Upstream version changed: review the exception');
  if (!audit || audit.auditReportVersion !== 2 || !audit.vulnerabilities || !lock?.packages) throw Error('Incomplete audit or lockfile');
  for (const node of EXPECTED_PATHS) {
    const pkg = lock.packages[node];
    if (!pkg || pkg.dev !== true || !policy.allowedVersions.includes(pkg.version)) throw Error('Affected dependency is no longer the reviewed dev-only version');
  }
  const findings = audit.vulnerabilities;
  const seen = new Set();
  function allowed(name, active = new Set()) {
    if (active.has(name) || !findings[name]) return false;
    const next = new Set(active); next.add(name);
    const item = findings[name];
    if (!Array.isArray(item.via) || item.via.length === 0 || !Array.isArray(item.nodes)) return false;
    return item.via.every(v => {
      if (typeof v === 'string') return allowed(v, next);
      if (!v || name !== 'picomatch' || v.name !== 'picomatch' || v.dependency !== 'picomatch'
        || v.source !== policy.npmAdvisoryId || v.url !== EXPECTED_URL || v.range !== '<=4.0.7'
        || item.nodes.some(n => !EXPECTED_PATHS.includes(n))) return false;
      seen.add(v.source); return true;
    });
  }
  for (const [name, item] of Object.entries(findings)) {
    if (['high', 'critical'].includes(item.severity) && !allowed(name)) throw Error(`Unapproved high/critical finding: ${name}`);
  }
  return seen.has(policy.npmAdvisoryId) ? 'PASS_WITH_ACCEPTED_RISK: GHSA-fc5q-39xc-vjpf remains unresolved' : 'PASS: no accepted advisory found';
}

function main() {
  const npm = process.env.npm_execpath;
  if (!npm || !fs.existsSync(npm)) throw Error('npm executable unavailable');
  const audit = spawnSync(process.execPath, [npm, 'audit', '--json'], {cwd: root, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  if (audit.stdout) process.stdout.write(audit.stdout);
  if (audit.stderr) process.stderr.write(audit.stderr);
  if (audit.error || ![0, 1].includes(audit.status)) throw Error('npm audit could not complete');
  const version = spawnSync(process.execPath, [npm, 'view', 'picomatch', 'version', '--json'], {cwd: root, encoding: 'utf8'});
  if (version.error || version.status !== 0) throw Error('Unable to check upstream picomatch version');
  const result = evaluate(JSON.parse(audit.stdout), JSON.parse(fs.readFileSync(path.join(root, 'security/audit-exception.json'))),
    JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'))), JSON.parse(version.stdout));
  console.log(result);
}
module.exports = {evaluate, main};
if (require.main === module) { try { main(); } catch (error) { console.error(`SECURITY_AUDIT_BLOCKED: ${error.message}`); process.exitCode = 1; } }
