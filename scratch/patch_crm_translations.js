const fs = require('fs');

let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

const missingKeysEn = {
    'crm_lead': 'Lead',
    'crm_pitch': 'Pitch',
    'crm_negotiation': 'Negotiation',
    'crm_won': 'Won',
    'crm_lost': 'Lost',
};

const missingKeysAr = {
    'crm_lead': 'مبدئي',
    'crm_pitch': 'عرض',
    'crm_negotiation': 'تفاوض',
    'crm_won': 'مكتسب',
    'crm_lost': 'مفقود',
};

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
        newEntries += `\n    ${k}: "${v}",`;
    }
    
    innerContent = newEntries + innerContent;
    dataContent = dataContent.substring(0, startIdx + blockName.length + 3) + innerContent + dataContent.substring(endIdx);
}

injectKeys('en', missingKeysEn);
injectKeys('ar', missingKeysAr);

fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Injected CRM translations");
