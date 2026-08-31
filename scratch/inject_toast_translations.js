const fs = require('fs');
const { toastTranslations } = require('./translations_mapping_toasts.js');

let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

const missingKeysEn = {};
const missingKeysAr = {};

for (const [englishString, data] of Object.entries(toastTranslations)) {
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
console.log("Successfully injected all toast translations to EN and AR blocks in data.js");

// Now update app.js
let appContent = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');
let replacedCount = 0;

for (const [englishString, data] of Object.entries(toastTranslations)) {
    // we want to replace `showToast('englishString'` with `showToast(t('key') || 'englishString'`
    const searchStr = `showToast('${englishString}'`;
    // Ensure we don't double-replace
    if (appContent.includes(searchStr)) {
        // Escape string for replace
        const escapedSearchStr = searchStr.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const replacementStr = `showToast(window.t('${data.key}') || '${englishString.replace(/'/g, "\\'")}'`;
        
        // global replacement
        const regex = new RegExp(escapedSearchStr, 'g');
        const countMatches = (appContent.match(regex) || []).length;
        if (countMatches > 0) {
            appContent = appContent.replace(regex, replacementStr);
            replacedCount += countMatches;
        }
    }
}

fs.writeFileSync('e:/HR.sys/js/app.js', appContent, 'utf8');
console.log(`Patched ${replacedCount} toast elements in app.js`);
