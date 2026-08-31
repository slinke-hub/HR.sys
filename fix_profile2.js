const fs = require('fs');
let code = fs.readFileSync('js/app.js', 'utf8');

const target = "    // Pre-fill employee name and department if available\n    const profile = currentUserProfile || await db.getUserProfile(currentUser?.id);";
const replacement = "    // Pre-fill employee name and department if available";

if (code.includes(target)) {
    code = code.replace(target, replacement);
    fs.writeFileSync('js/app.js', code);
    console.log('Fixed duplicate const successfully.');
} else {
    console.log('Target string not found.');
}
