const fs = require('fs');
let app = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const replaceTarget = `    const isAdmin = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole);
    const isHrManager = normalizedRole === 'HR_MANAGER' || /HR\\s*MANAGER/i.test(String(currentUserProfile?.job_title || ''));`;

const newCode = `    const isAdmin = ['ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN'].includes(normalizedRole);
    const isHrManager = normalizedRole === 'HR_MANAGER' || /HR\\s*MANAGER/i.test(String(currentUserProfile?.job_title || ''));
    
    const departments = await db.fetchDepartments();
    const managedDepartments = (departments || []).filter(department => department.head_id === currentUser?.id);
    const isManagerOrSupervisor = isAdmin || ['MANAGER', 'SUPERVISOR'].includes(normalizedRole) || /manager|supervisor/i.test(currentUserProfile?.job_title || '') || managedDepartments.length > 0;`;

app = app.replace(replaceTarget, newCode);

const replaceTarget2 = `if (approvalsNav) approvalsNav.style.display = (isAdmin || ['MANAGER', 'SUPERVISOR'].includes(normalizedRole) || isHussain) ? 'flex' : 'none';`;
const newCode2 = `if (approvalsNav) approvalsNav.style.display = (isManagerOrSupervisor || isHussain) ? 'flex' : 'none';`;

app = app.replace(replaceTarget2, newCode2);

fs.writeFileSync('e:/HR.sys/js/app.js', app, 'utf8');
console.log('Fixed approvals sidebar visibility for department heads/managers');
