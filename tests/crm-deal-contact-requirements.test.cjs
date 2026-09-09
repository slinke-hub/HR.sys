/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260909100000_crm_deal_contact_requirements.sql'), 'utf8');

const inputTag = id => html.match(new RegExp(`<[^>]+id="${id}"[^>]*>`))?.[0] || '';

assert.doesNotMatch(inputTag('crmDealAmount'), /\brequired\b/);
assert.doesNotMatch(inputTag('crmDealClosingDate'), /\brequired\b/);
assert.match(inputTag('crmDealFirstContactDate'), /\brequired\b/);
assert.match(inputTag('crmDealContactMethod'), /\brequired\b/);
assert.match(inputTag('crmDealAssignee'), /\brequired\b/);

assert.match(app, /amount:\s*amountValue === '' \? null : Number\(amountValue\)/);
assert.match(app, /!firstContactDateEl\?\.value \|\| !contactMethodEl\?\.value \|\| !assigneeVal/);
assert.match(app, /assigned_to:\s*assigneeVal/);
assert.doesNotMatch(app, /assigned_to:\s*assigneeVal \? assigneeVal : currentUser\.id/);

assert.match(migration, /ALTER COLUMN amount DROP NOT NULL/);
assert.match(migration, /ALTER COLUMN closing_date DROP NOT NULL/);
assert.match(migration, /IF TG_OP = 'INSERT'/);
assert.match(migration, /First contact date is required/);
assert.match(migration, /Contact method is required/);
assert.match(migration, /Deal assignee is required/);

console.log('CRM deal optional and required fields are aligned across the form and database.');
