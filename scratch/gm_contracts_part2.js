const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const contractDataTarget = /status: document\.getElementById\('contractStatus'\)\.value\s*\};/;
const contractDataNew = `status: document.getElementById('contractStatus').value,
        edited_by: window.formatEmployeeName(currentUserProfile) || null
    };`;

app = app.replace(contractDataTarget, contractDataNew);
fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
console.log('Updated app.js');

let db = fs.readFileSync('e:/HR.sys/js/db.js', 'utf8');
const dbFileTarget = /delete safeUpdates\.task_sub_type;/;
const dbFileNew = `delete safeUpdates.task_sub_type;
                    delete safeUpdates.edited_by;`;

db = db.replace(dbFileTarget, dbFileNew);
fs.writeFileSync('e:/HR.sys/js/db.js', db, 'utf8');
console.log('Updated db.js');
