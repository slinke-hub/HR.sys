const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

async function test() {
    // Read the supabase config from db.js
    const dbJs = fs.readFileSync('./js/db.js', 'utf8');
    const urlMatch = dbJs.match(/const SUPABASE_URL = '(.*?)';/);
    const keyMatch = dbJs.match(/const SUPABASE_ANON_KEY = '(.*?)';/);
    
    if (!urlMatch || !keyMatch) {
        console.error("Could not extract Supabase credentials from db.js");
        return;
    }
    
    const supabase = createClient(urlMatch[1], keyMatch[1]);
    
    // We must sign in as admin or HR manager to test this because of RLS
    // Let's try to just call the RPC. If it fails with 42501 Unauthorized, we know the RPC exists.
    // If it fails with something else, we will see it.
    
    const { data, error } = await supabase.rpc('create_user_by_admin', {
        new_email: 'test_admin_creation_fake@example.com',
        new_password: 'Password123!',
        new_role: 'EMPLOYEE',
        new_job_title: 'Tester',
        new_full_name: 'Test User',
        new_iqama: '1234567890',
        new_phone: '123456789',
        new_employee_id: 'EMP0001'
    });
    
    console.log("Data:", data);
    console.log("Error:", JSON.stringify(error, null, 2));
}

test();
