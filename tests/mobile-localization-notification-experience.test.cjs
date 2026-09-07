/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const data = fs.readFileSync(path.join(root, 'js', 'data.js'), 'utf8');
const components = fs.readFileSync(path.join(root, 'css', 'components.css'), 'utf8');
const android = fs.readFileSync(path.join(root, 'css', 'android.css'), 'utf8');

assert.match(components, /Universal compact modal shell for small phones/);
assert.match(components, /width: min\(100%, 440px\) !important/);
assert.match(components, /max-height: calc\(100dvh - \.7rem - env\(safe-area-inset-top\) - env\(safe-area-inset-bottom\)\) !important/);
assert.match(components, /\[style\*="grid-template-columns"\] \{ grid-template-columns: minmax\(0, 1fr\) !important; \}/);
assert.match(android, /max-height: calc\(100dvh - \.7rem - env\(safe-area-inset-top\) - env\(safe-area-inset-bottom\)\) !important/);

const context = {};
vm.createContext(context);
vm.runInContext(`${data};globalThis.__i18n=i18n`, context);
const referencedKeys = new Set();
for (const file of ['index.html', 'js/app.js', 'js/contract.js', 'js/payroll.js']) {
    const source = fs.readFileSync(path.join(root, file), 'utf8');
    for (const pattern of [/data-i18n(?:-placeholder|-title)?=["']([^"']+)["']/g, /\bt\(["']([^"']+)["']\)/g]) {
        let match;
        while ((match = pattern.exec(source))) {
            if (!match[1].includes('${')) referencedKeys.add(match[1]);
        }
    }
}
const missingArabic = [...referencedKeys].filter(key => !context.__i18n.ar?.[key]);
const missingEnglish = [...referencedKeys].filter(key => !context.__i18n.en?.[key]);
assert.deepEqual(missingArabic, [], `Missing Arabic keys: ${missingArabic.join(', ')}`);
assert.deepEqual(missingEnglish, [], `Missing English keys: ${missingEnglish.join(', ')}`);
assert.match(app, /let arabicTranslationObserver = null/);
assert.match(app, /new MutationObserver\(mutations =>/);
assert.match(app, /mutation\.addedNodes\.forEach\(scheduleArabicInterfaceTranslation\)/);

const marker = 'const arabicRuntimeUiText = Object.freeze({';
const runtimeStart = app.indexOf(marker) + marker.length - 1;
const runtimeEnd = app.indexOf('\n});\nconst arabicRuntimeUiTextLower', runtimeStart);
const runtimeArabic = vm.runInNewContext(`(${app.slice(runtimeStart, runtimeEnd + 2)})`);
const coveredEnglish = new Set(Object.keys(runtimeArabic).map(value => value.toLocaleLowerCase('en')));
Object.entries(context.__i18n.en).forEach(([key, value]) => {
    if (context.__i18n.ar[key]) coveredEnglish.add(String(value).trim().toLocaleLowerCase('en'));
});
const hardCodedPhrases = new Set();
for (const file of ['index.html', 'js/app.js', 'js/contract.js', 'js/payroll.js']) {
    const source = fs.readFileSync(path.join(root, file), 'utf8');
    const pattern = />\s*([^<>{}`$]{2,}?)\s*</g;
    let match;
    while ((match = pattern.exec(source))) {
        const phrase = match[1].replace(/&amp;/g, '&').replace(/&rsquo;/g, '’').replace(/\s+/g, ' ').trim();
        if (/^[A-Za-z][A-Za-z0-9 /&().,:;'’!?*+\-]{1,}$/.test(phrase) && /[A-Za-z]{2}/.test(phrase)) hardCodedPhrases.add(phrase);
    }
}
const uncoveredPhrases = [...hardCodedPhrases].filter(phrase => (
    phrase !== 'www.muqam.net'
    && !phrase.startsWith('String(value')
    && !coveredEnglish.has(phrase.toLocaleLowerCase('en'))
));
assert.deepEqual(uncoveredPhrases, [], `Untranslated UI phrases: ${uncoveredPhrases.join(' | ')}`);

assert.match(app, /const dingDongChimes = \[/);
assert.match(app, /frequency: 783\.99/);
assert.match(app, /frequency: 523\.25/);
assert.ok(app.indexOf('frequency: 783.99') < app.indexOf('frequency: 523.25'), 'Ding must play before dong');

console.log('Mobile modal, Arabic localization, and Dingdong notification tests passed.');
