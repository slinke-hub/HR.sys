const fs = require('fs');
let db = fs.readFileSync('e:/HR.sys/js/db.js', 'utf8');

const replaceTarget = `                    delete safeUpdates.task_list_id;
                    delete safeUpdates.assignee_ids;`;

const newCode = `                    delete safeUpdates.task_list_id;
                    delete safeUpdates.assignee_ids;
                    delete safeUpdates.task_department_id;
                    delete safeUpdates.task_sub_type;
                    delete safeUpdates.file_links;`;

db = db.replace(replaceTarget, newCode);
fs.writeFileSync('e:/HR.sys/js/db.js', db, 'utf8');
console.log('Fixed db.js safeUpdates');
