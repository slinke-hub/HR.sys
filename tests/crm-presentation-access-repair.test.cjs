/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const migration = read('supabase/migrations/20260915113000_fix_crm_presentation_submitter_access.sql');
const db = read('js/db.js');
const html = read('index.html');
const worker = read('sw.js');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.start_crm_presentation_approval/);
assert.match(migration, /IF NOT public\.can_access_crm\(auth\.uid\(\)\) THEN/);
assert.doesNotMatch(migration, /Only the deal creator, assignee, or management can send this request/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS completion_requested_by uuid/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS completion_requested_at timestamptz/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS completion_approved_by uuid/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS completion_approved_at timestamptz/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.start_crm_presentation_approval\(uuid, text\) TO authenticated/);
assert.match(db, /startCrmPresentationApproval Error:[\s\S]*message: error\?\.message/);
assert.match(html, /js\/db\.js\?v=2026091502/);
assert.match(worker, /muqam-hr-mobile-v231/);

console.log('CRM presentation submitter access repair tests passed.');
