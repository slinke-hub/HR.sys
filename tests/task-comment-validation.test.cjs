const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const appSource = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const dbSource = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

function sourceBetween(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  assert.ok(start >= 0 && end > start, `Unable to extract ${startMarker}`);
  return source.slice(start, end);
}

function createCommentHarness({ content = '', files = [], uploadResults = [] } = {}) {
  const elements = {
    detailsTaskId: { value: 'task-1' },
    taskCommentInput: {
      value: content,
      disabled: false,
      focusCount: 0,
      focus() { this.focusCount += 1; }
    },
    taskCommentAttachmentInput: { files, disabled: false },
    taskCommentSubmitButton: { disabled: false },
    taskCommentAttachButton: { disabled: false }
  };
  const calls = { uploads: [], comments: [], deletes: [], toasts: [], opened: [] };
  const db = {
    async uploadTaskAttachment(...args) {
      calls.uploads.push(args);
      return uploadResults.shift() || {
        success: true,
        url: `storage://task-attachments/task-1/user-1/${calls.uploads.length}-file.txt`,
        name: args[2].name
      };
    },
    async addTaskComment(...args) {
      calls.comments.push(args);
      return { success: true };
    },
    async deleteTaskAttachmentObjects(refs) {
      calls.deletes.push(refs);
      return { success: true };
    },
    async triggerWebhooks() { return { success: true }; }
  };
  const context = {
    console,
    currentLang: 'en',
    currentUser: { id: 'user-1' },
    currentView: 'tasks',
    db,
    document: { getElementById: id => elements[id] },
    window: {
      activeTaskDetail: { id: 'task-1' },
      clearTaskCommentAttachments() {},
      taskCache: {}
    },
    canInteractWithTask: () => true,
    showToast: (...args) => calls.toasts.push(args),
    taskDetailText: english => english,
    t: key => key,
    openTaskDetailsModal: id => calls.opened.push(id)
  };
  vm.createContext(context);
  const handlerSource = sourceBetween(
    appSource,
    'window.handleTaskCommentSubmit = async function (e) {',
    '\n};\n\nwindow.handleCreateSubTaskClick'
  ) + '\n};';
  vm.runInContext(handlerSource, context);
  return { context, elements, calls };
}

async function testCommentValidation() {
  const selectedFile = { name: 'evidence.pdf', size: 1024, type: 'application/pdf' };
  const invalid = createCommentHarness({ content: '   ', files: [selectedFile] });
  await invalid.context.window.handleTaskCommentSubmit({ preventDefault() {} });
  assert.equal(invalid.calls.uploads.length, 0, 'attachment-only submission uploaded a file');
  assert.equal(invalid.calls.comments.length, 0, 'attachment-only submission invoked the RPC');
  assert.equal(invalid.elements.taskCommentInput.focusCount, 1, 'empty comment input was not focused');
  assert.equal(invalid.calls.toasts[0]?.[1], 'warning', 'empty comment did not show a warning');
  assert.equal(invalid.elements.taskCommentAttachmentInput.files[0], selectedFile, 'selected file was cleared');

  const textOnly = createCommentHarness({ content: '  Valid comment  ' });
  await textOnly.context.window.handleTaskCommentSubmit({ preventDefault() {} });
  assert.equal(textOnly.calls.uploads.length, 0);
  assert.deepEqual(Array.from(textOnly.calls.comments[0].slice(0, 3)), ['task-1', 'user-1', 'Valid comment']);
  assert.deepEqual(Array.from(textOnly.calls.comments[0][3]), []);

  const textAndFile = createCommentHarness({ content: 'With attachment', files: [selectedFile] });
  await textAndFile.context.window.handleTaskCommentSubmit({ preventDefault() {} });
  assert.equal(textAndFile.calls.uploads.length, 1);
  assert.equal(textAndFile.calls.comments.length, 1);
  assert.equal(textAndFile.calls.comments[0][3].length, 1);

  const secondFile = { name: 'second.pdf', size: 1024, type: 'application/pdf' };
  const uploadFailure = createCommentHarness({
    content: 'Upload cleanup',
    files: [selectedFile, secondFile],
    uploadResults: [
      { success: true, url: 'storage://task-attachments/task-1/user-1/first.pdf', name: 'evidence.pdf' },
      { success: false, error: new Error('upload failed') }
    ]
  });
  await uploadFailure.context.window.handleTaskCommentSubmit({ preventDefault() {} });
  assert.equal(uploadFailure.calls.comments.length, 0);
  assert.deepEqual(Array.from(uploadFailure.calls.deletes[0]), ['storage://task-attachments/task-1/user-1/first.pdf']);
  assert.equal(uploadFailure.elements.taskCommentInput.disabled, false);
  assert.equal(uploadFailure.elements.taskCommentAttachmentInput.disabled, false);
}

function createDbMethodHarness() {
  const definitions = sourceBetween(
    dbSource,
    'const SIGNED_STORAGE_NEGATIVE_TTL_MS = 30000;',
    'const isMissingRpcError'
  );
  const resolverMethods = sourceBetween(
    dbSource,
    '    async resolveStorageReference(value, expiresIn = 300) {',
    '\n\n\n    // Translation API'
  );
  const addCommentMethod = sourceBetween(
    dbSource,
    '    async addTaskComment(taskId, userId, content, attachments = []) {',
    '\n    // ==========================================\n    // EMPLOYEE DOCUMENTS UPLOAD'
  ).trim().replace(/,$/, '');

  let now = 1000000;
  let session = { user: { id: 'user-a' } };
  let invokeImpl = async () => ({ data: { signedUrl: 'https://signed/a', expiresIn: 300 }, error: null });
  const calls = { auth: 0, invoke: 0, rpc: 0, flush: 0 };
  const context = {
    console: { warn() {} },
    Date: { now: () => now },
    PRIVATE_STORAGE_BUCKETS: new Set(['task-attachments']),
    parseStorageReference(value) {
      const match = String(value || '').match(/^storage:\/\/([^/]+)\/(.+)$/);
      return match ? { bucket: match[1], path: match[2] } : null;
    },
    supabaseClient: {
      auth: {
        async getSession() {
          calls.auth += 1;
          return { data: { session } };
        }
      },
      functions: {
        async invoke(...args) {
          calls.invoke += 1;
          return invokeImpl(...args);
        }
      },
      async rpc() {
        calls.rpc += 1;
        return { data: { id: 'comment-1' }, error: null };
      }
    }
  };
  vm.createContext(context);
  vm.runInContext(`
    ${definitions}
    const db = {
      ${resolverMethods}
      ${addCommentMethod},
      async flushTaskNotificationEmails() { calls.flush += 1; }
    };
    globalThis.testApi = {
      db,
      clearSignedStorageUrlCaches,
      setSignedStorageCacheUser
    };
  `, Object.assign(context, { calls }));
  return {
    db: context.testApi.db,
    calls,
    advance(ms) { now += ms; },
    setSession(value) { session = value; },
    setInvoke(fn) { invokeImpl = fn; },
    changeSession(value) {
      session = value;
      context.testApi.clearSignedStorageUrlCaches(value?.user?.id || null);
    }
  };
}

async function testDefensiveCommentValidation() {
  const harness = createDbMethodHarness();
  const rejected = await harness.db.addTaskComment('task-1', 'user-a', '   ', []);
  assert.equal(rejected.success, false);
  assert.match(rejected.error.message, /Comment text is required/);
  assert.equal(harness.calls.rpc, 0, 'empty comment reached the RPC');

  const accepted = await harness.db.addTaskComment('task-1', 'user-a', ' Valid ', []);
  assert.equal(accepted.success, true);
  assert.equal(harness.calls.rpc, 1);
  assert.equal(harness.calls.flush, 1);
}

async function testSignedUrlCaching() {
  const ref = 'storage://task-attachments/task-1/user-a/file.pdf';
  const harness = createDbMethodHarness();
  let release;
  harness.setInvoke(() => new Promise(resolve => { release = resolve; }));
  const first = harness.db.resolveStorageReference(ref);
  const second = harness.db.resolveStorageReference(ref);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(harness.calls.invoke, 1, 'concurrent requests were not deduplicated');
  release({ data: { signedUrl: 'https://signed/a', expiresIn: 300 }, error: null });
  assert.deepEqual(await Promise.all([first, second]), ['https://signed/a', 'https://signed/a']);

  assert.equal(await harness.db.resolveStorageReference(ref), 'https://signed/a');
  assert.equal(harness.calls.invoke, 1, 'positive cache was not reused');
  harness.advance(181000);
  harness.setInvoke(async () => ({ data: { signedUrl: 'https://signed/a2', expiresIn: 300 }, error: null }));
  assert.equal(await harness.db.resolveStorageReference(ref), 'https://signed/a2');
  assert.equal(harness.calls.invoke, 2, 'positive cache did not refresh near expiration');

  const failedRef = 'storage://task-attachments/task-1/user-a/denied.pdf';
  harness.setInvoke(async () => ({ data: null, error: new Error('Forbidden') }));
  assert.equal(await harness.db.resolveStorageReference(failedRef), '');
  assert.equal(await harness.db.resolveStorageReference(failedRef), '');
  assert.equal(harness.calls.invoke, 3, 'negative cache did not suppress the repeat');
  harness.advance(30001);
  assert.equal(await harness.db.resolveStorageReference(failedRef), '');
  assert.equal(harness.calls.invoke, 4, 'expired negative entry did not retry');

  harness.changeSession({ user: { id: 'user-b' } });
  harness.setInvoke(async () => ({ data: { signedUrl: 'https://signed/b', expiresIn: 300 }, error: null }));
  assert.equal(await harness.db.resolveStorageReference(ref), 'https://signed/b');
  assert.equal(harness.calls.invoke, 5, 'user B reused user A cache state');

  harness.changeSession(null);
  assert.equal(await harness.db.resolveStorageReference(ref), '');
  assert.equal(harness.calls.invoke, 5, 'signed URL request ran without an authenticated user');

  const authCallsBeforePublic = harness.calls.auth;
  assert.equal(await harness.db.resolveStorageReference('https://example.test/public.pdf'), 'https://example.test/public.pdf');
  assert.equal(harness.calls.auth, authCallsBeforePublic, 'public reference performed an auth lookup');
}

async function testLateResponseAndNotificationDeduplication() {
  const ref = 'storage://task-attachments/task-1/user-a/late.pdf';
  const harness = createDbMethodHarness();
  let release;
  harness.setInvoke(() => new Promise(resolve => { release = resolve; }));
  const staleRequest = harness.db.resolveStorageReference(ref);
  await new Promise(resolve => setImmediate(resolve));
  harness.changeSession({ user: { id: 'user-b' } });
  release({ data: { signedUrl: 'https://signed/user-a', expiresIn: 300 }, error: null });
  assert.equal(await staleRequest, '', 'late user-A URL escaped after the session changed');

  let releaseDuplicate;
  harness.setInvoke(() => new Promise(resolve => { releaseDuplicate = resolve; }));
  const duplicateBatch = harness.db.resolveStorageReferences([ref, ref]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(harness.calls.invoke, 2, 'duplicate notification links were not deduplicated');
  releaseDuplicate({ data: { signedUrl: 'https://signed/user-b', expiresIn: 300 }, error: null });
  assert.deepEqual(Array.from(await duplicateBatch), ['https://signed/user-b', 'https://signed/user-b']);
}

(async () => {
  await testCommentValidation();
  await testDefensiveCommentValidation();
  await testSignedUrlCaching();
  await testLateResponseAndNotificationDeduplication();
  console.log('task-comment-validation.test.cjs: PASS');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
