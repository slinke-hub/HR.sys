const fs = require('fs');
let appJs = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const oldStr = 'context.innerHTML = `<div class="teamwork-edit-list">Task list <strong>Inbox</strong></div><div class="teamwork-edit-tabs"><button type="button" class="active" onclick="setEditTaskTab(\'details\')">Details</button><button type="button" onclick="setEditTaskTab(\'advanced\')">Advanced options</button></div>`;';
const newStr = 'context.innerHTML = `<div class="teamwork-edit-list"><span data-i18n="html_task_list">Task list</span> <strong><span data-i18n="html_inbox">Inbox</span></strong></div><div class="teamwork-edit-tabs"><button type="button" class="active" onclick="setEditTaskTab(\'details\')" data-i18n="html_details">Details</button><button type="button" onclick="setEditTaskTab(\'advanced\')" data-i18n="html_advanced_options">Advanced options</button></div>`;';

if (appJs.includes(oldStr)) {
    appJs = appJs.replace(oldStr, newStr);
    fs.writeFileSync('e:/HR.sys/js/app.js', appJs);
    console.log('Successfully updated app.js');
} else {
    console.log('String not found in app.js. It may have already been updated.');
}
