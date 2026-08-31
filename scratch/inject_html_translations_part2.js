const fs = require('fs');
const { htmlTranslationsPart2 } = require('./translations_mapping_part2.js');

let htmlContent = fs.readFileSync('e:/HR.sys/index.html', 'utf8');
let lines = htmlContent.split('\n');
let replacedCount = 0;

for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (!line.includes('data-i18n') && !line.includes('<!--') && !line.includes('<script')) {
        for (const [englishString, data] of Object.entries(htmlTranslationsPart2)) {
            // Find > followed by whitespace then englishString then whitespace then <
            const regex = new RegExp('>\\s*' + englishString.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*<');
            const match = line.match(regex);
            if (match) {
                const index = match.index; // index of >
                const openingTagInnerEnd = index;
                line = line.substring(0, openingTagInnerEnd) + ` data-i18n="${data.key}"` + line.substring(openingTagInnerEnd);
                lines[i] = line;
                replacedCount++;
                break;
            }
        }
    }
}

fs.writeFileSync('e:/HR.sys/index.html', lines.join('\n'), 'utf8');
console.log('Patched ' + replacedCount + ' elements in index.html for part2.');
