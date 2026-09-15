/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const app = read('js/app.js');
const css = read('css/components.css');
const recognitionSource = read('js/document-ocr.js');

const sandbox = {
  window: {},
  document: { baseURI: 'http://localhost/' },
  URL
};
vm.runInNewContext(recognitionSource, sandbox);
const recognition = sandbox.window.EmployeeDocumentRecognition;

const english = recognition.parseBusinessCard(`
Acme Events LLC
Account Services Team
Sarah Johnson
Marketing Director
M: +966 50 123 4567
sarah.johnson@acme.sa
www.acme.sa
`, [
  { text: 'Acme Events LLC', height: 30, width: 230, confidence: 95 },
  { text: 'Account Services Team', height: 24, width: 250, confidence: 97 },
  { text: 'Sarah Johnson', height: 62, width: 310, confidence: 92 },
  { text: 'sarah.johnson@acme.sa', height: 15, width: 210, confidence: 96 }
]);
assert.equal(english.name, 'Sarah Johnson');
assert.equal(english.company, 'Acme Events LLC');
assert.equal(english.email, 'sarah.johnson@acme.sa');
assert.equal(english.phone, '+966501234567');

const arabic = recognition.parseBusinessCard(`
شركة مقام للفعاليات
محمد أحمد
مدير المبيعات
جوال: ٠٥٥ ١٢٣ ٤٥٦٧
mohamed@muqam.net
`);
assert.equal(arabic.name, 'محمد أحمد');
assert.equal(arabic.company, 'شركة مقام للفعاليات');
assert.equal(arabic.email, 'mohamed@muqam.net');
assert.equal(arabic.phone, '0551234567');

const visuallyStructured = recognition.parseBusinessCard(`
Sarah Johnson
MUQAM
Marketing Director
sarah @ muqam . net
+966 55 987 6543
King Fahd Road, Riyadh
`, [
  { text: 'Sarah Johnson', height: 66, width: 320, confidence: 94 },
  { text: 'MUQAM', height: 42, width: 185, confidence: 96 },
  { text: 'Marketing Director', height: 25, width: 230, confidence: 95 },
  { text: 'sarah @ muqam . net', height: 14, width: 190, confidence: 92 },
  { text: '+966 55 987 6543', height: 13, width: 170, confidence: 93 },
  { text: 'King Fahd Road, Riyadh', height: 12, width: 220, confidence: 90 }
]);
assert.equal(visuallyStructured.name, 'Sarah Johnson');
assert.equal(visuallyStructured.company, 'MUQAM');
assert.equal(visuallyStructured.email, 'sarah@muqam.net');
assert.equal(visuallyStructured.phone, '+966559876543');
assert.match(recognitionSource, /tessedit_pageseg_mode:[\s\S]*SPARSE_TEXT/);
assert.match(recognitionSource, /worker\.recognize\(file, \{\}, \{ text: true, blocks: true \}\)/);
assert.match(recognitionSource, /line\.bbox\?\.y1[\s\S]*line\.bbox\?\.y0/);
assert.match(recognitionSource, /right\.height - left\.height/);
assert.match(recognitionSource, /visualCompany/);
assert.match(recognitionSource, /replace\(\/\\s\*\@\\s\*\/g, '\@'\)/);

for (const id of [
  'crmClientBusinessCardSection', 'crmClientBusinessCardFile', 'crmClientBusinessCardPreview',
  'crmClientBusinessCardImage', 'crmClientBusinessCardStatus', 'crmClientBusinessCardRemove'
]) assert.match(html, new RegExp(`id="${id}"`), `Missing business-card import element ${id}`);

assert.match(html, /id="crmClientBusinessCardFile"[^>]*accept="image\/jpeg,image\/png,image\/webp,[^"]+"/);
assert.match(app, /showCRMClientModal\(null, true\)/);
assert.match(app, /window\.handleClientBusinessCardUpload = async function/);
assert.match(app, /extractor\.extractBusinessCard\(file/);
assert.match(app, /10 \* 1024 \* 1024/);
assert.match(app, /\['crmClientName', result\.name\]/);
assert.match(app, /\['crmClientCompany', result\.company\]/);
assert.match(app, /\['crmClientEmail', result\.email\]/);
assert.match(app, /\['crmClientPhone', result\.phone\]/);
assert.match(app, /crmClientBusinessCardScanVersion/);
assert.match(css, /\.crm-business-card-import/);
assert.match(css, /\.crm-business-card-preview img/);
assert.match(css, /@media \(max-width: 640px\)[\s\S]*\.crm-client-modal-content/);

console.log('English and Arabic business-card imports populate the reviewable client form.');
