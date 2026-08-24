const fs = require('fs');
const content = fs.readFileSync('e:/HR.sys/js/db.js', 'utf8');
const urlMatch = content.match(/const\s+SUPABASE_URL\s*=\s*['"]([^'"]+)['"]/);
const keyMatch = content.match(/const\s+SUPABASE_ANON_KEY\s*=\s*['"]([^'"]+)['"]/);

if (urlMatch && keyMatch) {
    const url = urlMatch[1];
    const key = keyMatch[1];
    
    Promise.all([
        fetch(`${url}/rest/v1/departments?select=count`, {
            headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
        }),
        fetch(`${url}/rest/v1/profiles?select=count`, {
            headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
        })
    ]).then(async responses => {
        const dCount = responses[0].headers.get('content-range');
        const pCount = responses[1].headers.get('content-range');
        console.log("Departments range:", dCount);
        console.log("Profiles range:", pCount);
        
        const dRes = await responses[0].json();
        const pRes = await responses[1].json();
        console.log("Departments preview:", dRes.slice(0, 2));
        console.log("Profiles preview:", pRes.slice(0, 2));
    });
}
