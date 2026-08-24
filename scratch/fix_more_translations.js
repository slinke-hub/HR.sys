const fs = require('fs');

let html = fs.readFileSync('index.html', 'utf8');

// Fix Add Watcher text
html = html.replace(/<input type="checkbox" id="editEnableWatchers"([^>]+)>\s+Add Watcher/g, '<input type="checkbox" id="editEnableWatchers"$1>\n                        <span data-i18n="ui_add_watcher">Add Watcher</span>');

fs.writeFileSync('index.html', html);

let data = fs.readFileSync('js/data.js', 'utf8');

const arAdditions = `
    html_department: "القسم",
    html_task_type: "نوع المهمة",`;
    
const enAdditions = `
    html_department: "Department",
    html_task_type: "Task Type",`;

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
console.log('Fixed missing translations');
