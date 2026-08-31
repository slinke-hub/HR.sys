const fs = require('fs');
let code = fs.readFileSync('js/app.js', 'utf8');

// 1. Add employees to employeeAllowedViews
code = code.replace(
    /const employeeAllowedViews = new Set\(\['dashboard', 'requests', 'time', 'tasks', 'documents'\]\);/g,
    "const employeeAllowedViews = new Set(['dashboard', 'requests', 'time', 'tasks', 'documents', 'employees']);"
);

// 2. Remove the line that hides employeesNav for EMPLOYEE
code = code.replace(
    /if \(employeesNav\) employeesNav\.style\.display = normalizedRole !== 'EMPLOYEE' \? 'flex' : 'none';/g,
    "if (employeesNav) employeesNav.style.display = 'flex';"
);

// 2b. Same thing in renderAdmin (it might exist there too)
code = code.replace(
    /if \(employeesNav\) employeesNav\.style\.display = \(currentUserRole === 'ADMIN' \|\| \(\(currentUserRole === 'MANAGER' \|\| currentUserRole === 'SUPERVISOR'\) \|\| currentUserRole === 'SUPERVISOR'\) \|\| window\.canCurrentUserEditContracts\(profile\)\) \? 'flex' : 'none';/g,
    "if (employeesNav) employeesNav.style.display = 'flex';"
);

// 3. Fix the visibility of users in renderEmployeesDirectory
code = code.replace(
    /\} else \{\s*\/\/\s*Employees see themselves, their team members, and their manager\s*visibleUsers = users\.filter\(u =>\s*u\.id === currentUser\.id \|\|\s*\(currentUser\.manager_id && u\.manager_id === currentUser\.manager_id\) \|\|\s*u\.id === currentUser\.manager_id\s*\);\s*\}/,
    "} else {\n          // Employees see ONLY themselves\n          visibleUsers = users.filter(u => u.id === currentUser.id);\n      }"
);

// 4. Ensure custody handover is hidden explicitly
code = code.replace(
    /if \(leaveCalculatorNav\) leaveCalculatorNav\.style\.display = \(isAdmin \|\| isHrManager\) \? 'flex' : 'none';/,
    "if (leaveCalculatorNav) leaveCalculatorNav.style.display = (isAdmin || isHrManager) ? 'flex' : 'none';\n    const custodyHandoverNav = document.getElementById('navCustodyHandover');\n    if (custodyHandoverNav) custodyHandoverNav.style.display = normalizedRole !== 'EMPLOYEE' ? 'flex' : 'none';"
);

// 5. Block access in renderCustodyHandover
code = code.replace(
    /async function renderCustodyHandover\(\) \{/,
    "async function renderCustodyHandover() {\n    if (currentUserRole === 'EMPLOYEE') return '<div class=\"page-header\"><h1 class=\"page-title\">Unauthorized</h1></div>';"
);

fs.writeFileSync('js/app.js', code);
console.log("Patched app.js successfully.");
