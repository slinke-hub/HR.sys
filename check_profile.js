const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

async function check() {
    const dbJs = fs.readFileSync('./js/db.js', 'utf8');
    const urlMatch = dbJs.match(/const SUPABASE_URL = '(.*?)';/);
    const keyMatch = dbJs.match(/const SUPABASE_ANON_KEY = '(.*?)';/);
    
    if (!urlMatch || !keyMatch) {
        console.error("Could not extract Supabase credentials from db.js");
        return;
    }
    
    const supabase = createClient(urlMatch[1], keyMatch[1]);
    
    // Test fetch the profile to see its role
    const { data, error } = await supabase.from('profiles').select('*').eq('email', 'privatepple@gmail.com');
    console.log("Profile check:", data);
    if (error) console.error("Error:", error);
}

check();
