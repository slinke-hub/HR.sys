const fs = require('fs');

let content = fs.readFileSync('js/data.js', 'utf8');

const arAdditions = `
    html_task_list: "قائمة المهام",
    html_inbox: "صندوق الوارد",
    html_details: "التفاصيل",
    html_advanced_options: "خيارات متقدمة",`;

// Find the start of the 'ar:' block and add the translations
const arIndex = content.indexOf('ar: {');
if (arIndex !== -1) {
    const insertPos = content.indexOf('\n', arIndex) + 1;
    content = content.slice(0, insertPos) + arAdditions + '\n' + content.slice(insertPos);
}

// Ensure the translations get updated in the UI when switching languages.
// Wait, translations are applied via applyTranslations() in app.js
fs.writeFileSync('js/data.js', content);
console.log('Added translations to data.js');
