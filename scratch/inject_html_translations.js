const fs = require('fs');
const { htmlTranslations } = require('./translations_mapping.js');

let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

const missingKeysEn = {};
const missingKeysAr = {};

for (const [englishString, data] of Object.entries(htmlTranslations)) {
    missingKeysEn[data.key] = englishString;
    missingKeysAr[data.key] = data.ar;
}

function injectKeys(blockName, keysMap) {
    let startIdx = dataContent.indexOf(`${blockName}: {`);
    if (startIdx === -1) return;
    
    let i = startIdx + blockName.length + 2;
    let braceCount = 0;
    while (i < dataContent.length) {
        if (dataContent[i] === '{') braceCount++;
        if (dataContent[i] === '}') {
            braceCount--;
            if (braceCount === 0) break;
        }
        i++;
    }
    let endIdx = i;
    
    let innerContent = dataContent.substring(startIdx + blockName.length + 3, endIdx);
    
    for (const [k, v] of Object.entries(keysMap)) {
        let regex = new RegExp(`^\\s*${k}\\s*:.*(?:,\\s*$|$)`, 'gm');
        innerContent = innerContent.replace(regex, '');
    }
    
    let newEntries = '';
    for (const [k, v] of Object.entries(keysMap)) {
        // escape quotes
        const safeV = v.replace(/"/g, '\\"');
        newEntries += `\n    ${k}: "${safeV}",`;
    }
    
    innerContent = newEntries + innerContent;
    
    dataContent = dataContent.substring(0, startIdx + blockName.length + 3) + innerContent + dataContent.substring(endIdx);
}

injectKeys('en', missingKeysEn);
injectKeys('ar', missingKeysAr);

fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Successfully injected all translations to EN and AR blocks in data.js");

// Now update index.html
let htmlContent = fs.readFileSync('e:/HR.sys/index.html', 'utf8');
let lines = htmlContent.split('\n');
let replacedCount = 0;

for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (!line.includes('data-i18n') && !line.includes('<!--') && !line.includes('<script')) {
        for (const [englishString, data] of Object.entries(htmlTranslations)) {
            // Check if the line has >englishString< exactly
            const index = line.indexOf(`>${englishString}<`);
            if (index !== -1) {
                // inject data-i18n
                const before = line.substring(0, index);
                const matchTagStart = before.lastIndexOf('<');
                if (matchTagStart !== -1) {
                    const insertPos = index;
                    line = line.substring(0, insertPos) + ` data-i18n="${data.key}">` + englishString + '<';
                    // We just appended '<', but we replaced '><', so we need to fix it:
                    // Actually, replace `>${englishString}<` with ` data-i18n="key">${englishString}<`
                    // Wait, this isn't safe if the tag is closed. E.g. `<span>Text</span>` -> index points to `>`.
                    // We need to inject into the opening tag.
                    const openingTagInnerEnd = index;
                    line = line.substring(0, openingTagInnerEnd) + ` data-i18n="${data.key}">` + line.substring(openingTagInnerEnd + 1);
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
