const fs = require('fs');
let code = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');

const newEnKeys = {
  html_task_list: 'Task list',
  html_inbox: 'Inbox',
  html_details: 'Details',
  html_advanced_options: 'Advanced options',
  ph_add_a_description: 'Add a description'
};

const newArKeys = {
  html_task_list: 'قائمة المهام',
  html_inbox: 'صندوق الوارد',
  html_details: 'التفاصيل',
  html_advanced_options: 'خيارات متقدمة',
  ph_add_a_description: 'أضف وصفاً'
};

// Insert into English block
const enStart = code.indexOf('en: {') + 5;
let enInsert = '';
for (let [k, v] of Object.entries(newEnKeys)) {
  if (!code.includes(k + ':')) {
      enInsert += `\n    ${k}: "${v}",`;
  }
}
code = code.substring(0, enStart) + enInsert + code.substring(enStart);

// Insert into Arabic block
const arStart = code.indexOf('ar: {') + 5;
let arInsert = '';
for (let [k, v] of Object.entries(newArKeys)) {
  if (!code.includes(k + ':')) {
      arInsert += `\n    ${k}: "${v}",`;
  }
}
code = code.substring(0, arStart) + arInsert + code.substring(arStart);

fs.writeFileSync('e:/HR.sys/js/data.js', code);
console.log('Modified data.js');
