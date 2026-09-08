const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const serviceWorker = fs.readFileSync(path.join(root, 'sw.js'), 'utf8');
const androidActivity = fs.readFileSync(path.join(root, 'android', 'app', 'src', 'main', 'java', 'net', 'muqam', 'hr', 'MainActivity.java'), 'utf8');

assert.match(app, /const APP_HISTORY_VIEW_KEY = 'muqamView'/);
assert.match(app, /window\.history\[shouldReplace \? 'replaceState' : 'pushState'\]/);
assert.match(app, /window\.addEventListener\('popstate'/);
assert.match(app, /void renderView\(previousView, true\)/);
assert.match(app, /window\.history\.back\(\)/);
assert.match(app, /if \(!isBack\) syncAppBrowserHistory\(viewId, viewId === 'login'\)/);
assert.match(app, /closeTransientUiForHistoryNavigation\(\)/);
assert.match(html, /js\/app\.js\?v=2026090801/);
assert.match(serviceWorker, /muqam-hr-mobile-v177/);
assert.match(androidActivity, /getOnBackPressedDispatcher\(\)\.addCallback/);
assert.match(androidActivity, /webView\.canGoBack\(\)/);
assert.match(androidActivity, /webView\.goBack\(\)/);

console.log('Mobile browser and Android Back navigation use the app view history.');
