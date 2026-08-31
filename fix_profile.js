const fs = require('fs');
let code = fs.readFileSync('js/app.js', 'utf8');

code = code.replace(
    /    \/\/ Pre-fill employee name and department if available\n    const profile = currentUserProfile \|\| await db\.getUserProfile\(currentUser\?\.id\);/,
    "    // Pre-fill employee name and department if available"
);

fs.writeFileSync('js/app.js', code);
console.log('Fixed duplicate const declaration in renderCustodyHandover.');
