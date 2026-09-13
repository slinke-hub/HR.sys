/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const recognitionSource = fs.readFileSync(path.join(root, 'js/document-ocr.js'), 'utf8');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const localServer = fs.readFileSync(path.join(root, 'scripts/serve-local.mjs'), 'utf8');

const browser = { window: {}, document: { baseURI: 'https://sys.muqam.net/' }, URL };
vm.createContext(browser);
vm.runInContext(recognitionSource, browser);
const { parseMetadata } = browser.window.EmployeeDocumentRecognition;

assert.deepEqual(
  { ...parseMetadata('Owner Name: Ahmed Hassan\nExpiry Date: 2028-04-17') },
  { ownerName: 'Ahmed Hassan', expirationDate: '2028-04-17' }
);
assert.deepEqual(
  { ...parseMetadata('اسم المالك: محمد أحمد\nتاريخ الانتهاء: ١٧/٠٤/٢٠٢٨') },
  { ownerName: 'محمد أحمد', expirationDate: '2028-04-17' }
);
assert.equal(parseMetadata('Issue date 01/01/2024\nRenewal date 01/01/2028').expirationDate, '');
assert.equal(parseMetadata('Document date: 2028-04-17').expirationDate, '');

assert.match(app, /name: 'Montasir',[\s\S]*email: 'montasir\.hr@muqam\.net'/);
assert.match(app, /window\.autoPopulateEmployeeDocumentMetadata = async function/);
assert.match(app, /value="\$\{escapeHTML\(EMPLOYEE_DOCUMENT_DEFAULT_RESPONSIBLE\.name\)\}"/);
assert.match(app, /id="empOwnerEmail" class="form-control">/);
assert.match(app, /id="empOwnerPhone" class="form-control">/);
assert.match(db, /owner_email: documentRecord\.ownerEmail \|\| null/);
assert.match(db, /owner_phone: documentRecord\.ownerPhone \|\| null/);
assert.doesNotMatch(html, /id="employeeDocumentOwnerEmail" class="form-control" required/);
assert.doesNotMatch(html, /id="employeeDocumentOwnerPhone" class="form-control" required/);
assert.match(html, /js\/vendor\/tesseract\/tesseract\.min\.js/);
assert.match(html, /js\/document-ocr\.js/);
assert.match(localServer, /\['\.mjs', 'text\/javascript; charset=utf-8'\]/);
assert.match(localServer, /'wasm-unsafe-eval'/);

for (const file of [
  'js/vendor/tesseract/tesseract.min.js',
  'js/vendor/tesseract/worker.min.js',
  'js/vendor/tesseract/core/tesseract-core-lstm.wasm.js',
  'js/vendor/tesseract/lang/eng.traineddata.gz',
  'js/vendor/tesseract/lang/ara.traineddata.gz',
  'js/vendor/pdfjs/pdf.min.mjs',
  'js/vendor/pdfjs/pdf.worker.min.mjs'
]) assert.ok(fs.statSync(path.join(root, file)).size > 0, `${file} should be vendored`);

console.log('Local document metadata recognition and optional contact checks passed.');
