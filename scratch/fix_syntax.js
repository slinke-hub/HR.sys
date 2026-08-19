const fs = require('fs');

// Fix app.js
let appContent = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');
appContent = appContent.replace(/\\\`<p>\$\{t\('ui_no_recent_logins'\) \|\| 'No recent logins\.'\}<\/p>\\\`/g, "`<p>${t('ui_no_recent_logins') || 'No recent logins.'}</p>`");
fs.writeFileSync('e:/HR.sys/js/app.js', appContent, 'utf8');
console.log("Fixed syntax error in app.js");

// Fix data.js
let dataContent = fs.readFileSync('e:/HR.sys/js/data.js', 'utf8');
// Remove dangling "users_"
dataContent = dataContent.replace(/users_\s*\n/g, '');
fs.writeFileSync('e:/HR.sys/js/data.js', dataContent, 'utf8');
console.log("Fixed syntax error in data.js");
