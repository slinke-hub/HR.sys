/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const app = read('js/app.js');
const db = read('js/db.js');
const css = read('css/components.css');
const migration = read('supabase/migrations/20260915200000_attachment_versioning_and_project_sharing.sql');

assert.match(migration, /ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS visible_to_project_assignee BOOLEAN NOT NULL DEFAULT FALSE/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.archive_crm_deal_attachments/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.archive_task_attachments/);
assert.match(migration, /CREATE FUNCTION public\.list_project_shared_attachments/);
assert.match(migration, /attachment\.is_archived = FALSE/);
assert.match(migration, /attachment\.visible_to_project_assignee = TRUE/);
assert.match(migration, /auth\.uid\(\) = ANY\(COALESCE\(project\.assigned_people/);
assert.doesNotMatch(db.match(/async replaceDealPresentationAttachments[\s\S]*?async logDealActivity/)?.[0] || '', /storage\.from\('crm-deal-files'\)\.remove\(previousPaths\)/);

assert.match(db, /async fetchProjectSharedAttachments\(projectId\)/);
assert.match(db, /rpc\('list_project_shared_attachments'/);
assert.match(db, /async setProjectAttachmentVisibility\(attachmentType, attachmentId, visible\)/);
assert.match(db, /async archiveTaskAttachments\(taskId, keepIds = \[\]\)/);
assert.match(db, /async archiveDealAttachments\(dealId, categories, keepIds = \[\]\)/);
assert.match(db, /\.eq\('is_archived', false\)/);

assert.match(app, /window\.setProjectAttachmentVisibility = async function/);
assert.match(app, /function projectAttachmentList\(attachments, canManage\)/);
assert.match(app, /db\.fetchProjectSharedAttachments\(id\)/);
assert.match(app, /class="project-attachments-section project-detail-span-2"/);
assert.match(app, /db\.archiveTaskAttachments\(task\.id, newAttachmentIds\)/);
assert.match(app, /replaceCategories:/);
assert.match(app, /data-deal-attachment-project-visible/);
assert.match(app, /data-equipment-project-visible/);
assert.match(app, /db\.archiveDealAttachments\(dealId, \['PHOTO'\], newEquipmentAttachmentIds\)/);
assert.match(html, /id="presentationQuoteProjectVisible"/);
assert.match(html, /id="presentationIdentityProjectVisible"/);
assert.match(html, /id="editTaskFilesProjectVisible"/);
assert.match(css, /\.project-attachment-grid/);
assert.match(css, /\.attachment-sharing-toggle/);

console.log('Attachment versioning and project-assignee sharing tests passed.');
