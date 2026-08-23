const fs = require('fs');
const content = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// 1. Replace initCustomTranslations
let newContent = content.replace(/window\.initCustomTranslations = function\(\) \{[\s\S]*?\};\r?\nwindow\.initCustomTranslations\(\);/m, 
`window.initCustomTranslations = async function() {
    try {
        const saved = await db.fetchSystemTranslations();
        if (saved && Array.isArray(saved)) {
            saved.forEach(t => {
                if (t.trans_en && typeof i18n !== 'undefined' && i18n.en) i18n.en[t.trans_key] = t.trans_en;
                if (t.trans_ar && typeof i18n !== 'undefined' && i18n.ar) i18n.ar[t.trans_key] = t.trans_ar;
            });
        }
    } catch(e) {
        console.error("Error loading system translations:", e);
    }
};`);

// 2. Add window.saveAllTranslations and remove window.saveSingleTranslation
newContent = newContent.replace(/window\.saveSingleTranslation = function\(key\) \{[\s\S]*?\};/,
`window.saveAllTranslations = async function() {
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
    });
    
    if (updates.length > 0) {
        const res = await db.saveSystemTranslationsBatch(updates);
        if(res.success) {
            showToast('All translations saved successfully', 'success');
        } else {
            showToast('Failed to save translations to database', 'danger');
        }
    } else {
        showToast('No translations to save', 'warning');
    }
};`);

// 3. Update deleteTranslationKey
newContent = newContent.replace(/window\.deleteTranslationKey = function\(key\) \{[\s\S]*?renderView\('translations'\);\r?\n    \}\);\r?\n\};/, 
`window.deleteTranslationKey = function(key) {
    window.showConfirmModal("Delete Translation Key", \`Are you sure you want to delete "\${key}"?\`, async () => {
        if (typeof i18n !== 'undefined') {
            delete i18n.en[key];
            delete i18n.ar[key];
        }
        const res = await db.deleteSystemTranslation(key);
        if(res.success) {
            showToast("Translation key removed", "warning");
        } else {
            showToast("Failed to remove translation from database", "danger");
        }
        renderView('translations');
    });
};`);

// 4. Update handleAddTranslationSubmit
newContent = newContent.replace(/window\.handleAddTranslationSubmit = function\(e\) \{[\s\S]*?renderView\('translations'\);\r?\n\};/,
`window.handleAddTranslationSubmit = async function(e) {
    e.preventDefault();
    const key = document.getElementById('newTransKey').value.trim().toLowerCase().replace(/\\s+/g, '_');
    const enVal = document.getElementById('newTransEn').value.trim();
    const arVal = document.getElementById('newTransAr').value.trim();

    if (!key) {
        showToast("Translation key is required", "danger");
        return;
    }

    if (typeof i18n !== 'undefined') {
        i18n.en[key] = enVal || key;
        i18n.ar[key] = arVal || key;
    }

    const res = await db.saveSystemTranslationsBatch([{ trans_key: key, trans_en: enVal || key, trans_ar: arVal || key }]);
    if(res.success) {
        showToast("Translation key added successfully!", "success");
    } else {
        showToast("Failed to add translation to database", "danger");
    }
    closeAddTranslationModal();
    renderView('translations');
};`);

// 5. Remove persistCustomTranslations and resetTranslationsToDefault
newContent = newContent.replace(/window\.persistCustomTranslations = function\(\) \{[\s\S]*?\};\r?\n/, "");
newContent = newContent.replace(/window\.resetTranslationsToDefault = function\(\) \{[\s\S]*?\};\r?\n/, "");

// Remove persistCustomTranslations from importTranslationsJSON
newContent = newContent.replace(/\bwindow\.persistCustomTranslations\(\);?\r?\n/g, "");

// 6. Fix renderTranslationsPage HTML (remove individual save button, remove reset button, add Save All)
newContent = newContent.replace(/<button class="btn-primary"[^>]*onclick="saveSingleTranslation\([^>]*>\s*<i[^>]*><\/i>\s*<\/button>/g, "");

newContent = newContent.replace(/<button class="btn-secondary" style="color:var\(--color-danger\);" onclick="resetTranslationsToDefault\(\)">[\s\S]*?<\/button>/, "");

// Add Save All button next to Add Translation Key
newContent = newContent.replace(/<button class="btn-primary" onclick="showAddTranslationModal\(\)">/, 
`<button class="btn-primary" onclick="saveAllTranslations()" style="background-color: var(--color-success); border-color: var(--color-success);">
                    <i data-lucide="save" style="width:16px;height:16px;margin-right:4px;"></i> Save All Changes
                </button>
                <button class="btn-primary" onclick="showAddTranslationModal()">`);

// 7. Update initApp
newContent = newContent.replace(/async function initApp\(\) \{\r?\n    updateTranslations\(\);\r?\n\r?\n    \/\/ Check for existing session/,
`async function initApp() {
    await window.initCustomTranslations();
    updateTranslations();
    
    // Subscribe to realtime updates for translations
    if (typeof db !== 'undefined' && db.subscribeToTranslations) {
        db.subscribeToTranslations(payload => {
            if (payload.eventType === 'INSERT' || payload.eventType === 'UPDATE') {
                const { trans_key, trans_en, trans_ar } = payload.new;
                if (trans_en && typeof i18n !== 'undefined' && i18n.en) i18n.en[trans_key] = trans_en;
                if (trans_ar && typeof i18n !== 'undefined' && i18n.ar) i18n.ar[trans_key] = trans_ar;
            } else if (payload.eventType === 'DELETE') {
                const { trans_key } = payload.old;
                if (typeof i18n !== 'undefined') {
                    delete i18n.en[trans_key];
                    delete i18n.ar[trans_key];
                }
            }
            updateTranslations();
            if (currentView === 'translations') {
                renderView('translations');
            }
        });
    }

    // Check for existing session`);

fs.writeFileSync('e:/HR.sys/js/app.js', newContent, 'utf8');
console.log('App.js patched successfully via node');
