/* eslint-env node */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261122120000_crm_attachment_uploader_delete.sql'), 'utf8');

assert.match(app, /canDeleteAttachment = !isMq08Viewer[\s\S]*?file\.uploaded_by[\s\S]*?canCurrentUserDeleteCrmDeals/,
  'Attachment delete control should be offered to its uploader and CRM leadership');
assert.match(app, /window\.deleteCrmDealAttachment = function/,
  'The deal attachment list must provide a delete action');
assert.match(app, /db\.removeDealAttachment\(attachment\.id, attachment\.storage_reference \|\| attachment\.file_url\)/,
  'The UI must call the secured attachment deletion service with its storage reference');
assert.match(db, /rpc\('delete_crm_deal_attachment_secure'/,
  'Attachment metadata deletion must use the secured RPC');
assert.match(db, /storage\.from\(reference\.bucket\)\.remove\(\[reference\.path\]\)/,
  'The stored file should be removed after its metadata is deleted');
assert.match(migration, /owner = auth\.uid\(\) OR public\.can_delete_crm_deal\(auth\.uid\(\)\)/,
  'Only the uploader or CRM leadership may remove stored CRM files');
assert.match(migration, /FOR DELETE TO authenticated/,
  'Stored file deletion must remain authenticated-only');

console.log('CRM_ATTACHMENT_DELETE=PASS');
