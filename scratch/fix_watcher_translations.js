const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

html = html.replace(/<span>Add Watchers<\/span>/g, '<span data-i18n="ui_add_watcher">Add Watchers</span>');
html = html.replace(/>Select watchers<\/button>/g, ' data-i18n="ui_select_watchers">Select watchers</button>');
html = html.replace(/placeholder="Search employees..." aria-label="Search employees"/g, 'placeholder="Search employees..." data-i18n-placeholder="ph_search_employees" aria-label="Search employees"');

fs.writeFileSync('index.html', html);

let data = fs.readFileSync('js/data.js', 'utf8');

const arAdditions = `
    ui_add_watcher: "إضافة مراقبين",
    ui_select_watchers: "تحديد مراقبين",
    ph_search_employees: "ابحث عن موظفين...",`;
    
const enAdditions = `
    ui_add_watcher: "Add Watchers",
    ui_select_watchers: "Select watchers",
    ph_search_employees: "Search employees...",`;

const arIndex = data.indexOf('ar: {');
if (arIndex !== -1) {
    const insertPos = data.indexOf('\n', arIndex) + 1;
    data = data.slice(0, insertPos) + arAdditions + '\n' + data.slice(insertPos);
}

const enIndex = data.indexOf('en: {');
if (enIndex !== -1) {
    const insertPos = data.indexOf('\n', enIndex) + 1;
    data = data.slice(0, insertPos) + enAdditions + '\n' + data.slice(insertPos);
}

fs.writeFileSync('js/data.js', data);
console.log('Fixed watcher translations in HTML and data.js');
