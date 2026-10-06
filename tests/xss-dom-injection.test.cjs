const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js/app.js'), 'utf8');
const crm = fs.readFileSync(path.join(root, 'src/crm-dashboard.jsx'), 'utf8');

function loadFunction(name, context = {}) {
  const start = app.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `Expected ${name} helper`);
  const brace = app.indexOf('{', start);
  let depth = 0;
  let end = -1;
  for (let i = brace; i < app.length; i++) {
    if (app[i] === '{') depth++;
    if (app[i] === '}' && --depth === 0) { end = i + 1; break; }
  }
  assert.notEqual(end, -1, `Could not extract ${name}`);
  const sandbox = { URL, window: { location: { origin: 'https://hrsys.example' } }, repairTextEncoding: value => value, ...context };
  vm.runInNewContext(`${app.slice(start, end)}; this.result = ${name};`, sandbox);
  return sandbox.result;
}

const escapeHTML = loadFunction('escapeHTML');
const safeExternalUrl = loadFunction('safeExternalUrl');
const safeReceiptUrl = loadFunction('safeReceiptUrl', { safeExternalUrl });
const hostile = `"><img src=x onerror=alert(1)><script>alert(1)</script>'`;
const escaped = escapeHTML(hostile);
assert.equal(escaped.includes('<script'), false);
assert.equal(escaped.includes('<img'), false);
assert.match(escaped, /&quot;&gt;/);
assert.match(escaped, /&#039;/);

assert.equal(safeExternalUrl('javascript:alert(1)'), '');
assert.equal(safeExternalUrl('data:text/html,<svg onload=alert(1)>'), '');
assert.equal(safeExternalUrl('http://[malformed'), '');
assert.equal(safeExternalUrl('https://news.example/article'), 'https://news.example/article');
assert.equal(safeExternalUrl('/news/article'), 'https://hrsys.example/news/article');
assert.equal(safeReceiptUrl('javascript:alert(1)'), '');
assert.equal(safeReceiptUrl('data:text/html;base64,PHNjcmlwdD4='), '');
assert.equal(safeReceiptUrl('data:application/pdf;base64,JVBERi0x'), 'data:application/pdf;base64,JVBERi0x');

// CRM card values are rendered as React text nodes in the active dashboard,
// while legacy HTML interpolation is explicitly encoded at each text sink.
for (const expression of [
  'escapeHTML(d.title ||',
  'escapeHTML(d.crm_clients ? d.crm_clients.name',
  'escapeHTML(d.closing_date)',
  'escapeHTML(window.formatEmployeeName(users.find'
]) assert.ok(app.includes(expression), `Legacy CRM sink must encode ${expression}`);
assert.match(crm, /\{clientName\}/);
assert.match(crm, /\{details\}/);
assert.match(crm, /safeExternalUrl\?\.\(profile\.avatar_url\)/);
assert.match(crm, /src=\{avatarUrl\}/);

// Employee names are no longer serialized into executable onclick arguments;
// the contract modal escapes names when placing them back into HTML.
assert.doesNotMatch(app, /navigateToContract\('\$\{u\.id\}', '\$\{\(window\.formatEmployeeName/);
assert.match(app, /<h2 style="margin:0">\$\{escapeHTML\(t\('users_contract'\)[\s\S]*escapeHTML\(empName\)\}/);
assert.match(app, /<p class="page-subtitle">\$\{escapeHTML\(currentContractEmployeeName/);

// Stored community content and profile images are context-encoded/scheme-checked.
assert.match(app, /community-message-author">\$\{escapeHTML\(window\.formatEmployeeName\(m\.profiles\)/);
assert.match(app, /community-message-copy">\$\{escapeHTML\(m\.message/);
assert.match(app, /safeExternalUrl\(m\.profiles\?\.avatar_url\)/);
assert.match(app, /<td>\$\{escapeHTML\(c\.name \|\| ''\)\}<\/td>/);
assert.match(app, /<td>\$\{escapeHTML\(e\.description \|\| ''\)\}<\/td>/);
assert.match(app, /safeReceiptUrl\(e\.receipt_base64\)/);

// News URLs must pass the centralized HTTP(S)-only allowlist; invalid links
// are rendered as inert text rather than an anchor with an empty href.
assert.match(app, /const safeLink = safeExternalUrl\(item\.link\)/);
assert.match(app, /safeLink \? `<a href="\$\{escapeHTML\(safeLink\)\}"/);
assert.match(app, /: `<span>\$\{titleHtml\}<\/span>`/);

console.log('Targeted hostile-input XSS, attribute, and URL-scheme regressions passed.');
