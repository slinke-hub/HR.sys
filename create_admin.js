const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://bbbetcdioiaozdjkvwxu.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiYmV0Y2Rpb2lhb3pkamt2d3h1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTM0NjQsImV4cCI6MjEwMTU4OTQ2NH0.GhV7HsGnAXA8Zb_IV3hxhwI9qmbM3qhcuWRMSXKUNcw';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function main() {
    console.log("Signing up user privatepple@gmail.com...");
    const { data, error } = await supabase.auth.signUp({
        email: 'privatepple@gmail.com',
        password: '0912577754'
    });
    
    if (error) {
        console.error("Error:", error.message);
        if (error.message.includes('already registered')) {
            console.log("User is already registered.");
        }
    } else {
        console.log("Success! User ID:", data.user?.id);
    }
}

main();
