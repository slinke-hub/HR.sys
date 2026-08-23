const fs = require('fs');
const content = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

let newContent = content;

// 1. Update saveAllTranslations to only push changed rows
const oldSaveAll = `window.saveAllTranslations = async function() {
    const rows = document.querySelectorAll('.trans-row');
    const updates = [];
    rows.forEach(row => {
        const key = row.dataset.key;
        const enVal = document.getElementById('trans_en_' + key)?.value || '';
        const arVal = document.getElementById('trans_ar_' + key)?.value || '';
        
        if (typeof i18n !== 'undefined') {
            i18n.en[key] = enVal;
            i18n.ar[key] = arVal;
        }
        updates.push({ trans_key: key, trans_en: enVal, trans_ar: arVal });
    });`;

const newSaveAll = `window.saveAllTranslations = async function() {
    const rows = document.querySelectorAll('.trans-row');
    const updates = [];
    rows.forEach(row => {
        const key = row.dataset.key;
        const enVal = document.getElementById('trans_en_' + key)?.value || '';
        const arVal = document.getElementById('trans_ar_' + key)?.value || '';
        
        if (typeof i18n !== 'undefined') {
            if (i18n.en[key] !== enVal || i18n.ar[key] !== arVal) {
                i18n.en[key] = enVal;
                i18n.ar[key] = arVal;
                updates.push({ trans_key: key, trans_en: enVal, trans_ar: arVal });
            }
        } else {
            updates.push({ trans_key: key, trans_en: enVal, trans_ar: arVal });
        }
    });`;

newContent = newContent.replace(oldSaveAll, newSaveAll);

// 2. Update Realtime listener to not use renderView('translations')
const oldListener = `            updateTranslations();
            if (currentView === 'translations') {
                renderView('translations');
            }`;

const newListener = `            updateTranslations();
            if (currentView === 'translations') {
                if (payload.eventType === 'INSERT' || payload.eventType === 'UPDATE') {
                    const { trans_key, trans_en, trans_ar } = payload.new;
                    const enInput = document.getElementById('trans_en_' + trans_key);
                    const arInput = document.getElementById('trans_ar_' + trans_key);
                    if (enInput && document.activeElement !== enInput) enInput.value = trans_en;
                    if (arInput && document.activeElement !== arInput) arInput.value = trans_ar;
                } else if (payload.eventType === 'DELETE') {
                    const { trans_key } = payload.old;
                    const row = document.querySelector(\`.trans-row[data-key="\${trans_key.toLowerCase()}"]\`);
                    if (row) row.remove();
                }
            }`;

newContent = newContent.replace(oldListener, newListener);

fs.writeFileSync('e:/HR.sys/js/app.js', newContent, 'utf8');
console.log('App.js patched to fix page refreshing');
