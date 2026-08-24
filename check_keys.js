const fs = require('fs');
const content = fs.readFileSync('e:/HR.sys/js/db.js', 'utf8');
const urlMatch = content.match(/const\s+SUPABASE_URL\s*=\s*['"]([^'"]+)['"]/);
const keyMatch = content.match(/const\s+SUPABASE_ANON_KEY\s*=\s*['"]([^'"]+)['"]/);

if (urlMatch && keyMatch) {
    console.log("URL:", urlMatch[1]);
    console.log("KEY:", keyMatch[1].substring(0, 10) + "...");
} else {
    console.log("Could not find keys");
}
