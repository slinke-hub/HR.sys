const fs = require('fs');

let appJs = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const target = `\${!isEmployee && r.status === 'Pending' ? \``;
const replacement = `\${!isEmployee && r.status === 'Pending' && r.employee_id !== currentUser?.id ? \``;

appJs = appJs.replace(target, replacement);

fs.writeFileSync('e:/HR.sys/js/app.js', appJs, 'utf8');

console.log("Updated app.js to prevent managers/admins from approving their own requests.");
