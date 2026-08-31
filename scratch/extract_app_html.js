const fs = require('fs');
const app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');
const lines = app.split('\n');
const untranslated = new Set();
lines.forEach(line => {
    const match = line.match(/>([^<$]{2,})</);
    if (match && !match[1].includes('i18n') && match[1].trim().length > 1 && !match[1].includes('${')) {
        untranslated.add(match[1].trim());
    }
});
console.log(Array.from(untranslated).slice(0, 30).join('\n'));
console.log('Total untranslated HTML strings in app.js:', untranslated.size);
