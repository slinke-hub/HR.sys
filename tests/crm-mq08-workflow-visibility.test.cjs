/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const app = read('js/app.js');
const css = read('css/components.css');
const data = read('js/data.js');
const html = read('index.html');

for (const id of [
  'dealLifecycleSection', 'dealDetailsSection', 'workflowSetupSection',
  'dealApprovalProgressSection', 'dealDocumentsSection', 'dealDocumentsTitle',
  'dealAttachmentForm', 'dealAttachmentList', 'dealProjectSection', 'dealActivitySection'
]) assert.match(html, new RegExp(`id="${id}"`), `Missing deal workflow element ${id}`);

assert.match(app, /const isMq08Viewer = isMq08Profile\(\)/);
assert.match(app, /lifecycleSection\.hidden = isMq08Viewer/);
assert.match(app, /activitySection\.hidden = isMq08Viewer/);
assert.match(app, /attachmentForm\.hidden = isMq08Viewer/);
assert.match(app, /setupSection\.hidden = isMq08Viewer/);
assert.match(app, /projectSection\.hidden = isMq08Viewer \|\| !workflow\.project/);
assert.match(app, /documentsTitle\.dataset\.i18n = isMq08Viewer \? 'crm_attached_documents' : 'crm_documents_photos'/);
assert.match(app, /if \(isMq08Viewer\) documentsSection\.hidden = false/);
assert.match(app, /const canDecide = !isMq08Viewer && step\.status === 'PENDING'/);
assert.match(css, /\.deal-attachment-form\[hidden\] \{ display: none !important; \}/);
assert.match(data, /crm_attached_documents: "Attached Documents"/);
assert.match(data, /crm_attached_documents: "المستندات المرفقة"/);

console.log('MQ-08 read-only CRM workflow visibility tests passed.');
