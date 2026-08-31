const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'js', 'app.js');
let content = fs.readFileSync(targetFile, 'utf8');

// Replace the HTML part
const htmlRegex = /<div\s+class="form-group\s+col-span-6">\s*<label\s+class="form-label">\$\{t\('prof_fn'\)\}<\/label>\s*<input\s+type="text"\s+id="profileFullName"\s+class="form-control"\s+value="\$\{escapeHTML\(profile\.full_name\s*\|\|\s*''\)\}"\s+placeholder="\$\{t\('users_fn_ph'\)\}">\s*<\/div>/g;

content = content.replace(htmlRegex, '');

// Replace the JS part
const jsRegex = /const\s+fullName\s*=\s*document\.getElementById\('profileFullName'\)\.value\.trim\(\);/g;

content = content.replace(jsRegex, "const fullName = currentUserProfile?.full_name || '';");

fs.writeFileSync(targetFile, content, 'utf8');
console.log("Successfully removed Full Name from profile settings using regex");
