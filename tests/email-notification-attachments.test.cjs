const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const emailFunction = fs.readFileSync(path.join(root, 'supabase', 'functions', 'task-notification-email', 'index.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260912104500_email_attachments_and_photos.sql'), 'utf8');

// 1. Verify Edge Function handles photo preview rendering and document lists
assert.match(emailFunction, /isImageFile/);
assert.match(emailFunction, /fileIcon/);
assert.match(emailFunction, /resolveAttachment/);
assert.match(emailFunction, /Photos &amp; Images/);
assert.match(emailFunction, /Attached Files &amp; Documents/);
assert.match(emailFunction, /createSignedUrl/);
assert.match(emailFunction, /email-assets/);
assert.match(emailFunction, /task_attachments/);
assert.match(emailFunction, /task_comments/);
assert.match(emailFunction, /expenses/);
assert.match(emailFunction, /receipt_base64/);
assert.match(emailFunction, /resendAttachments/);

// 2. Verify SQL migration captures task attachments, comment attachments, and expense receipts
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.queue_task_notification/);
assert.match(migration, /public\.task_attachments/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.queue_request_notification/);
assert.match(migration, /workflow_row\.source_table = 'expenses'/);
assert.match(migration, /receipt_base64 IS NOT NULL/);

console.log('Email notification attachments, uploaded files, and photos checks passed successfully.');
