const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
const helperStart = source.indexOf("const PRIVATE_STORAGE_BUCKETS = new Set([");
const helperEnd = source.indexOf('\nif (window.hrRuntimeConfigError)', helperStart);
const resolverStart = source.indexOf('    async resolveStorageReference(value, expiresIn = 300) {');
const resolverEnd = source.indexOf('\n    async resolveStorageReferences', resolverStart);
assert.ok(helperStart >= 0 && helperEnd > helperStart, 'storage cache helpers exist');
assert.ok(resolverStart >= 0 && resolverEnd > resolverStart, 'signed URL resolver exists');

let now = 1_800_000_000_000;
const FakeDate = class extends Date { static now() { return now; } };
const sandbox = { Date: FakeDate, URL, console: { warn() {} } };
vm.createContext(sandbox);
vm.runInContext(`
  ${source.slice(helperStart, helperEnd)}
  let supabaseClient = null;
  const db = { ${source.slice(resolverStart, resolverEnd).trim()} };
  this.api = {
    db,
    setClient(value) { supabaseClient = value; },
    clear: clearSignedStorageUrlCaches,
    setUser: setSignedStorageCacheUser
  };
`, sandbox, { timeout: 1000 });

let activeUser = 'user-a';
let invokeCount = 0;
let nextResponse = { data: { signedUrl: 'https://signed.invalid/a', expiresIn: 300 }, error: null };
let getSessionCount = 0;
const client = {
  auth: { async getSession() { getSessionCount += 1; return { data: { session: activeUser ? { user: { id: activeUser } } : null } }; } },
  functions: { async invoke(name, options) {
    assert.equal(name, 'file-signed-url');
    assert.deepEqual(JSON.parse(JSON.stringify(options.body)), { bucket: 'task-attachments', path: 'task/file.pdf', expiresIn: 300 });
    invokeCount += 1;
    return typeof nextResponse === 'function' ? nextResponse() : nextResponse;
  } }
};
sandbox.api.setClient(client);

async function run() {
  const privateRef = 'storage://task-attachments/task/file.pdf';
  const first = await sandbox.api.db.resolveStorageReference(privateRef);
  assert.equal(first, 'https://signed.invalid/a');
  const cached = await sandbox.api.db.resolveStorageReference(privateRef);
  assert.equal(cached, first);
  assert.equal(invokeCount, 1, 'positive cache avoids another signing request');

  activeUser = 'user-b';
  nextResponse = { data: { signedUrl: 'https://signed.invalid/b', expiresIn: 300 }, error: null };
  assert.equal(await sandbox.api.db.resolveStorageReference(privateRef), 'https://signed.invalid/b');
  assert.equal(invokeCount, 2, 'the same private key is independently resolved for another user');

  activeUser = null;
  assert.equal(await sandbox.api.db.resolveStorageReference(privateRef), '');
  assert.equal(invokeCount, 2, 'sign-out fails closed before signing');

  activeUser = 'user-a';
  sandbox.api.clear('user-a');
  let settleConcurrent;
  nextResponse = () => new Promise(resolve => { settleConcurrent = resolve; });
  const concurrentA = sandbox.api.db.resolveStorageReference(privateRef);
  const concurrentB = sandbox.api.db.resolveStorageReference(privateRef);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(invokeCount, 3, 'concurrent resolution issues one signing request');
  settleConcurrent({ data: { signedUrl: 'https://signed.invalid/concurrent', expiresIn: 300 }, error: null });
  assert.deepEqual(await Promise.all([concurrentA, concurrentB]), [
    'https://signed.invalid/concurrent', 'https://signed.invalid/concurrent'
  ]);

  sandbox.api.clear('user-a');
  let negativeInvokes = 0;
  nextResponse = async () => { negativeInvokes += 1; return { data: null, error: { status: 403 } }; };
  assert.equal(await sandbox.api.db.resolveStorageReference(privateRef), '');
  assert.equal(await sandbox.api.db.resolveStorageReference(privateRef), '');
  assert.equal(negativeInvokes, 1, 'negative cache suppresses repeated failure within its TTL');
  now += 30_001;
  nextResponse = async () => { negativeInvokes += 1; return { data: { signedUrl: 'https://signed.invalid/recovered', expiresIn: 300 }, error: null }; };
  assert.equal(await sandbox.api.db.resolveStorageReference(privateRef), 'https://signed.invalid/recovered');
  assert.equal(negativeInvokes, 2, 'negative cache expires after 30 seconds');

  sandbox.api.clear('user-a');
  let settleStale;
  nextResponse = () => new Promise(resolve => { settleStale = resolve; });
  const staleRequest = sandbox.api.db.resolveStorageReference(privateRef);
  await new Promise(resolve => setImmediate(resolve));
  sandbox.api.clear('user-b');
  activeUser = 'user-b';
  settleStale({ data: { signedUrl: 'https://signed.invalid/stale-user-a', expiresIn: 300 }, error: null });
  assert.equal(await staleRequest, '', 'late response is rejected after session identity changes');
  nextResponse = { data: { signedUrl: 'https://signed.invalid/current-user-b', expiresIn: 300 }, error: null };
  assert.equal(await sandbox.api.db.resolveStorageReference(privateRef), 'https://signed.invalid/current-user-b');

  const sessionsBeforePublic = getSessionCount;
  const publicRef = 'https://example.invalid/storage/v1/object/public/public-bucket/public/file.png';
  assert.equal(await sandbox.api.db.resolveStorageReference(publicRef), publicRef);
  assert.equal(getSessionCount, sessionsBeforePublic, 'public references bypass private signing');

  console.log('Signed URL cache behavior tests passed: positive/negative caching, TTL, deduplication, user isolation, sign-out, late responses, and public bypass.');
}

run().catch(error => { console.error(error); process.exitCode = 1; });
