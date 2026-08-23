import sys
import re

filename = r'e:\HR.sys\js\app.js'
with open(filename, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update initCustomTranslations and remove immediate call
old_init = '''window.initCustomTranslations = function() {
    try {
        const saved = localStorage.getItem('custom_i18n');
        if (saved) {
            const parsed = JSON.parse(saved);
            if (parsed.en && typeof i18n !== 'undefined' && i18n.en) Object.assign(i18n.en, parsed.en);
            if (parsed.ar && typeof i18n !== 'undefined' && i18n.ar) Object.assign(i18n.ar, parsed.ar);
        }
    } catch(e) {
        console.error("Error loading custom translations:", e);
    }
};
window.initCustomTranslations();'''

new_init = '''window.initCustomTranslations = async function() {
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
};'''
content = content.replace(old_init, new_init)


# 2. Update saveSingleTranslation
old_save = '''window.saveSingleTranslation = function(key) {
    const enVal = document.getElementById(	rans_en_)?.value || '';
    const arVal = document.getElementById(	rans_ar_)?.value || '';

    if (typeof i18n !== 'undefined') {
        i18n.en[key] = enVal;
        i18n.ar[key] = arVal;
    }

    window.persistCustomTranslations();
    showToast(t('trans_saved') || 'Translation updated successfully', 'success');
};'''

new_save = '''window.saveSingleTranslation = async function(key) {
    const enVal = document.getElementById(	rans_en_)?.value || '';
    const arVal = document.getElementById(	rans_ar_)?.value || '';

    if (typeof i18n !== 'undefined') {
        i18n.en[key] = enVal;
        i18n.ar[key] = arVal;
    }

    const res = await db.saveSystemTranslation(key, enVal, arVal);
    if(res.success) {
        showToast(t('trans_saved') || 'Translation updated successfully', 'success');
    } else {
        showToast('Failed to save translation to database', 'danger');
    }
};'''
content = content.replace(old_save, new_save)


# 3. Update deleteTranslationKey
old_delete = '''window.deleteTranslationKey = function(key) {
    window.showConfirmModal("Delete Translation Key", Are you sure you want to delete ""?, () => {
        if (typeof i18n !== 'undefined') {
            delete i18n.en[key];
            delete i18n.ar[key];
        }
        window.persistCustomTranslations();
        showToast("Translation key removed", "warning");
        renderView('translations');
    });
};'''

new_delete = '''window.deleteTranslationKey = function(key) {
    window.showConfirmModal("Delete Translation Key", Are you sure you want to delete ""?, async () => {
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
};'''
# Fix interpolation issues in python strings with backticks
content = content.replace(old_delete.replace('""', '""'), new_delete.replace('""', '""'))


# 4. Update handleAddTranslationSubmit
old_add = '''window.handleAddTranslationSubmit = function(e) {
    e.preventDefault();
    const key = document.getElementById('newTransKey').value.trim().toLowerCase().replace(/\s+/g, '_');
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

    window.persistCustomTranslations();
    showToast("Translation key added successfully!", "success");
    closeAddTranslationModal();
    renderView('translations');
};'''

new_add = '''window.handleAddTranslationSubmit = async function(e) {
    e.preventDefault();
    const key = document.getElementById('newTransKey').value.trim().toLowerCase().replace(/\s+/g, '_');
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

    const res = await db.saveSystemTranslation(key, enVal || key, arVal || key);
    if(res.success) {
        showToast("Translation key added successfully!", "success");
    } else {
        showToast("Failed to add translation to database", "danger");
    }
    closeAddTranslationModal();
    renderView('translations');
};'''
# fix backslash s in python string
old_add = old_add.replace('\s+', '\\\\s+')
new_add = new_add.replace('\s+', '\\\\s+')
content = content.replace(old_add, new_add)


# 5. Remove persistCustomTranslations and resetTranslationsToDefault
old_funcs = '''window.persistCustomTranslations = function() {
    try {
        if (typeof i18n !== 'undefined') {
            localStorage.setItem('custom_i18n', JSON.stringify({ en: i18n.en, ar: i18n.ar }));
        }
    } catch(e) {
        console.error("Failed to save translations to localStorage", e);
    }
};

window.resetTranslationsToDefault = function() {
    window.showConfirmModal("Reset Translations", "Are you sure you want to reset all custom translations to defaults?", () => {
        localStorage.removeItem('custom_i18n');
        ['en', 'ar'].forEach(language => {
            Object.keys(i18n[language] || {}).forEach(key => delete i18n[language][key]);
            Object.assign(i18n[language], defaultTranslationsSnapshot[language] || {});
        });
        updateTranslations();
        renderView('translations');
        showToast('Translations reset to defaults.', 'success');
    });
};'''

content = content.replace(old_funcs, "")

# Remove window.persistCustomTranslations() from importTranslationsJSON
content = content.replace('            window.persistCustomTranslations();\n', '')


# 6. Remove Reset button from UI
old_reset_btn = '''<button class="btn-secondary" style="color:var(--color-danger);" onclick="resetTranslationsToDefault()">
                    <i data-lucide="rotate-ccw" style="width:16px;height:16px;margin-right:4px;"></i> Reset
                </button>'''
content = content.replace(old_reset_btn, "")


# 7. Update initApp
old_init_app = '''async function initApp() {
    updateTranslations();

    // Check for existing session'''

new_init_app = '''async function initApp() {
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

    // Check for existing session'''
content = content.replace(old_init_app, new_init_app)

with open(filename, 'w', encoding='utf-8') as f:
    f.write(content)

print('Patched app.js successfully')
