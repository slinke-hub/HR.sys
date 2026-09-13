/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const data = fs.readFileSync(path.join(root, 'js/data.js'), 'utf8');

assert.match(app, /const expiredDocs = documentExpiryStates\.filter\(\(\{ expiryInfo \}\) => expiryInfo\.daysLeft !== null && expiryInfo\.daysLeft <= 0\)/);
assert.match(app, /const expiringDocs = documentExpiryStates\.filter\(\(\{ expiryInfo \}\) => expiryInfo\.daysLeft > 0 && expiryInfo\.daysLeft <= 30\)/);
assert.match(app, /t\('docs_expired'\)/);
assert.match(app, /openDocumentsByExpiryStatus\('expired'\)/);
assert.match(app, /openDocumentsByExpiryStatus\('expiring'\)/);
assert.match(app, /document-expiry-name-table/);
assert.match(app, /documentStatusFilter === 'expired'/);
assert.match(app, /daysLeft !== null && daysLeft > 0 && daysLeft <= 30/);
assert.match(app, /dateMatch = String\(expirationDate\)\.trim\(\)\.match/);
assert.match(app, /if \(daysLeft <= 0\)[\s\S]*doc_status_expired/);
assert.match(data, /docs_expired: "Expired Documents"/);
assert.match(data, /docs_expired: "مستندات منتهية"/);
assert.match(data, /doc_filter_all: "All documents"/);
assert.match(data, /doc_filter_all: "جميع المستندات"/);

console.log('Document expiry status checks passed.');
