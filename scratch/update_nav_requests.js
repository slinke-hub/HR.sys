const fs = require('fs');

// Update index.html
let htmlContent = fs.readFileSync('e:/HR.sys/index.html', 'utf8');

// 1. Remove "All Requests" item
// Look for data-i18n="nav_all_requests"
htmlContent = htmlContent.replace(/<a href="#" class="nav-item" data-view="requests">\s*<i data-lucide="inbox"><\/i>\s*<span data-i18n="nav_all_requests">All Requests<\/span>\s*<\/a>/, '');

// 2. Remove style="display: none !important;" from departments nav link
htmlContent = htmlContent.replace(/<a href="#" class="nav-item" data-view="departments" style="display: none !important;">/, '<a href="#" class="nav-item" data-view="departments">');

fs.writeFileSync('e:/HR.sys/index.html', htmlContent, 'utf8');


// Update app.js
let appContent = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

// Add departmentsNav in updateAuthUI
let target1 = "const employeesNav = document.querySelector('.nav-item[data-view=\"employees\"]');";
let replace1 = "const employeesNav = document.querySelector('.nav-item[data-view=\"employees\"]');\n        const departmentsNav = document.querySelector('.nav-item[data-view=\"departments\"]');";
appContent = appContent.replace(target1, replace1);

let target2 = "if (employeesNav) employeesNav.style.display = (currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) ? 'flex' : 'none';";
let replace2 = "if (employeesNav) employeesNav.style.display = (currentUserRole === 'ADMIN' || ((currentUserRole === 'MANAGER' || currentUserRole === 'SUPERVISOR') || currentUserRole === 'SUPERVISOR')) ? 'flex' : 'none';\n        if (departmentsNav) departmentsNav.style.display = currentUserRole === 'ADMIN' ? 'flex' : 'none';";
appContent = appContent.replace(target2, replace2);

// Filter requests to only currentUser.id
let reqTarget = "let leaves = await db.fetchLeaveRequests(isManagerOrAdmin ? null : currentUser?.id);\n    let docs = await db.fetchDocuments(isManagerOrAdmin ? null : currentUser?.id);\n    let expenses = await db.fetchExpenses(isManagerOrAdmin ? null : currentUser?.id);";
let reqReplace = "let leaves = await db.fetchLeaveRequests(currentUser?.id);\n    let docs = await db.fetchDocuments(currentUser?.id);\n    let expenses = await db.fetchExpenses(currentUser?.id);";
appContent = appContent.replace(reqTarget, reqReplace);

// Remove the older filtering logic where manager gets team requests
let teamReqTarget = `if (currentUserRole !== 'ADMIN') {
            leaves = leaves.filter(r => teamIds.includes(r.employee_id));
            docs = docs.filter(r => teamIds.includes(r.employee_id));
            expenses = expenses.filter(r => teamIds.includes(r.employee_id));
        }`;
// But teamReqTarget might have different formatting, let's just use regex
appContent = appContent.replace(/if \(currentUserRole !== 'ADMIN'\) \{\s*leaves = leaves\.filter\(r => teamIds\.includes\(r\.employee_id\)\);\s*docs = docs\.filter\(r => teamIds\.includes\(r\.employee_id\)\);\s*expenses = expenses\.filter\(r => teamIds\.includes\(r\.employee_id\)\);\s*\}/, '');

fs.writeFileSync('e:/HR.sys/js/app.js', appContent, 'utf8');

console.log("Updated navigation logic and request filtering");
