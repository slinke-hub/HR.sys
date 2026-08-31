const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const target = `    if (approvalsNav) approvalsNav.style.display = (isManagerOrSupervisor || isHussain) ? 'flex' : 'none';`;
const replacement = `    const isManagerOrSupervisor = isAdmin || isHrManager || window.currentUserProfile?.role === 'MANAGER' || /head|manager|supervisor/i.test(window.currentUserProfile?.job_title || '');
    if (approvalsNav) approvalsNav.style.display = (isManagerOrSupervisor || isHussain) ? 'flex' : 'none';`;

app = app.replace(target, replacement);

fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
console.log('Fixed ReferenceError in updateSidebarVisibility');
