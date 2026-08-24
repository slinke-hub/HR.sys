const fs = require('fs');
const content = fs.readFileSync('e:/HR.sys/js/db.js', 'utf8');
const urlMatch = content.match(/const\s+SUPABASE_URL\s*=\s*['"]([^'"]+)['"]/);
const keyMatch = content.match(/const\s+SUPABASE_ANON_KEY\s*=\s*['"]([^'"]+)['"]/);

if (urlMatch && keyMatch) {
    const url = urlMatch[1];
    const key = keyMatch[1];
    
    Promise.all([
        fetch(`${url}/rest/v1/departments?select=*&limit=1`, {
            headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
        }),
        fetch(`${url}/rest/v1/profiles?select=*&limit=1`, {
            headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
        })
    ]).then(async responses => {
        const dRes = await responses[0].json();
        const pRes = await responses[1].json();
        console.log("Departments:", dRes.length);
        console.log("Profiles:", pRes.length);
        if (dRes.length > 0) console.log("Dept example:", dRes[0]);
    });
}
