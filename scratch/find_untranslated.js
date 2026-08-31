const fs = require('fs');
const html = fs.readFileSync('e:/HR.sys/index.html', 'utf8');
const lines = html.split('\n');
const untranslated = [];
lines.forEach((line, i) => {
    if (!line.includes('data-i18n') && !line.includes('<!--') && !line.includes('<script')) {
        const match = line.match(/>([^<]{2,})</);
        if (match && match[1].trim().length > 1 && !match[1].includes('${') && !match[1].trim().startsWith('&')) {
            untranslated.push(i + 1 + ': ' + line.trim());
        }
    }
});
console.log(untranslated.slice(0, 30).join('\n'));
console.log('Total untranslated in index.html:', untranslated.length);
