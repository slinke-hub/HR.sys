const fs = require('fs');
let code = fs.readFileSync('js/app.js', 'utf8');

// 1. Update updateSidebarVisibility for Custody Handover
code = code.replace(
    /if \(custodyHandoverNav\) custodyHandoverNav\.style\.display = normalizedRole !== 'EMPLOYEE' \? 'flex' : 'none';/g,
    "if (custodyHandoverNav) custodyHandoverNav.style.display = (isAdmin || isHrManager) ? 'flex' : 'none';"
);

// 2. Update renderCustodyHandover authorization check
code = code.replace(
    /async function renderCustodyHandover\(\) \{\n    if \(currentUserRole === 'EMPLOYEE'\) return '<div class=\"page-header\"><h1 class=\"page-title\">Unauthorized<\/h1><\/div>';/g,
    "async function renderCustodyHandover() {\n    const profile = currentUserProfile || await db.getUserProfile(currentUser?.id);\n    const isAdmin = String(currentUserRole || '').toUpperCase() === 'ADMIN';\n    const isHrManager = String(profile?.job_title || '').trim().toUpperCase() === 'HR MANAGER';\n    if (!isAdmin && !isHrManager) return '<div class=\"page-header\"><h1 class=\"page-title\">Unauthorized</h1></div>';"
);

fs.writeFileSync('js/app.js', code);
console.log('Patched app.js for Custody Handover visibility.');
