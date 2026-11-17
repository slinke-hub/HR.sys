const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {evaluate} = require('../scripts/security-audit.cjs');
const root = path.join(__dirname, '..');
const policy = JSON.parse(fs.readFileSync(path.join(root, 'security/audit-exception.json')));
const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json')));
const now = Date.parse('2026-11-17T12:00:00Z');
const advisory = {source:1247710, name:'picomatch', dependency:'picomatch', url:'https://github.com/advisories/GHSA-fc5q-39xc-vjpf', range:'<=4.0.7'};
const report = {auditReportVersion:2, vulnerabilities:{
  picomatch:{severity:'high', via:[advisory], nodes:['node_modules/picomatch','node_modules/tinyglobby/node_modules/picomatch']},
  tailwindcss:{severity:'high', via:['picomatch'], nodes:['node_modules/tailwindcss']}
}};
assert.match(evaluate(report, policy, lock, '4.0.7', now), /PASS_WITH_ACCEPTED_RISK/);
const added = structuredClone(report);
added.vulnerabilities.other = {severity:'high', via:[{source:1,url:'https://example.invalid'}],nodes:['node_modules/other']};
assert.throws(() => evaluate(added,policy,lock,'4.0.7',now), /Unapproved/);
const mixed = structuredClone(report);
mixed.vulnerabilities.picomatch.via.push({source:2,name:'picomatch',dependency:'picomatch',url:'https://example.invalid',range:'*'});
assert.throws(() => evaluate(mixed,policy,lock,'4.0.7',now), /Unapproved/);
assert.throws(() => evaluate(report,{...policy, advisory:'wrong'},lock,'4.0.7',now), /Invalid/);
assert.throws(() => evaluate(report,policy,lock,'4.0.7',Date.parse('2026-11-24T00:00:00Z')), /expired/);
assert.throws(() => evaluate(report,policy,lock,'4.0.8',now), /Upstream/);
const runtimeLock = structuredClone(lock); runtimeLock.packages['node_modules/picomatch'].dev = false;
assert.throws(() => evaluate(report,policy,runtimeLock,'4.0.7',now), /dev-only/);
const source = fs.readFileSync(path.join(root,'scripts/security-audit.cjs'),'utf8');
assert.match(source, /\[npm, 'audit', '--json'\]/);
assert.match(source, /process\.stdout\.write\(audit\.stdout\)/);
console.log('ADVISORY_EXCEPTION_FAIL_CLOSED_TESTS=PASS');
