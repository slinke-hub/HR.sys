const fs = require('fs');
const html = fs.readFileSync('e:/HR.sys/index.html', 'utf8');
const lines = html.split('\n');
const untranslated = new Set();
lines.forEach((line, i) => {
    if (!line.includes('data-i18n') && !line.includes('<!--') && !line.includes('<script')) {
        const match = line.match(/>([^<]{2,})</);
        if (match && match[1].trim().length > 1 && !match[1].includes('${') && !match[1].trim().startsWith('&')) {
            untranslated.add(match[1].trim());
        }
    }
});
fs.writeFileSync('e:/HR.sys/scratch/index_untranslated.json', JSON.stringify([...untranslated], null, 2));
