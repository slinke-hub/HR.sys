const fs = require('fs');
const { htmlTranslations } = require('./translations_mapping.js');
const { htmlTranslationsPart2 } = require('./translations_mapping_part2.js');

const allTranslations = { ...htmlTranslations, ...htmlTranslationsPart2 };

let htmlContent = fs.readFileSync('e:/HR.sys/index.html', 'utf8');
let lines = htmlContent.split('\n');
let replacedCount = 0;

for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (!line.includes('data-i18n') && !line.includes('<!--') && !line.includes('<script')) {
        for (const [englishString, data] of Object.entries(allTranslations)) {
            const index = line.indexOf(`>${englishString}<`);
            if (index !== -1) {
                const before = line.substring(0, index);
                const matchTagStart = before.lastIndexOf('<');
                if (matchTagStart !== -1) {
                    const tagContent = line.substring(matchTagStart, index);
                    // insert data-i18n at the end of the opening tag (before the >)
                    const newTag = tagContent + ` data-i18n="${data.key}"`;
                    line = line.substring(0, matchTagStart) + newTag + line.substring(index);
                    lines[i] = line;
                    replacedCount++;
                    break;
                }
            }
        }
    }
}

fs.writeFileSync('e:/HR.sys/index.html', lines.join('\n'), 'utf8');
console.log(`Patched ${replacedCount} elements in index.html`);
