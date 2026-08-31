const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const dbJsContent = fs.readFileSync(path.join(__dirname, 'js', 'db.js'), 'utf8');
const urlMatch = dbJsContent.match(/const\s+SUPABASE_URL\s*=\s*['"]([^'"]+)['"]/);
const keyMatch = dbJsContent.match(/const\s+SUPABASE_ANON_KEY\s*=\s*['"]([^'"]+)['"]/);

if (!urlMatch || !keyMatch) {
    console.error("Could not find Supabase credentials");
    process.exit(1);
}

const supabaseUrl = urlMatch[1];
const supabaseAnonKey = keyMatch[1];
const supabase = createClient(supabaseUrl, supabaseAnonKey);

async function checkColumn() {
    const { data, error } = await supabase.from('profiles').select('*').limit(1);
    if (error) {
        console.error("Error:", error);
    } else if (data && data.length > 0) {
        console.log("Columns:", Object.keys(data[0]));
    } else {
        console.log("No data found.");
    }
}

checkColumn();
