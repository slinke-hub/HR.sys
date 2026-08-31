const fs = require('fs');
let code = fs.readFileSync('js/contract.js', 'utf8');

code = code.replace(
    /if \(!contractId \|\| !employeeId\) \{/,
    "if (currentUserRole === 'EMPLOYEE' && employeeId !== currentUser?.id) return '<div style=\"padding: 20px;\">Unauthorized</div>';\n    if (!contractId || !employeeId) {"
);

fs.writeFileSync('js/contract.js', code);
console.log('Patched contract.js security.');
