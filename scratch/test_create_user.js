const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://bbbetcdioiaozdjkvwxu.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiYmV0Y2Rpb2lhb3pkamt2d3h1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTM0NjQsImV4cCI6MjEwMTU4OTQ2NH0.GhV7HsGnAXA8Zb_IV3hxhwI9qmbM3qhcuWRMSXKUNcw';
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function testCreateUser() {
    // We must authenticate as admin first to test the RPC
    const { data: loginData, error: loginError } = await supabase.auth.signInWithPassword({
        email: 'privatepple@gmail.com',
        password: '0912577754'
    });

    if (loginError) {
        console.error("Login failed:", loginError);
        return;
    }

    console.log("Logged in as admin. Testing create_user_by_admin RPC...");

    const { data, error } = await supabase.rpc('create_user_by_admin', {
        new_email: 'test_create_employee@example.com',
        new_password: 'password123',
        new_role: 'EMPLOYEE',
        new_job_title: 'Tester',
        new_full_name: 'Test Employee',
        new_iqama: '1234567890',
        new_phone: '0500000000'
    });

    if (error) {
        console.error("RPC Error:", JSON.stringify(error, null, 2));
    } else {
        console.log("Success! Data:", data);
    }
}

testCreateUser();
