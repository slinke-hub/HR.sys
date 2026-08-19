const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
    'https://bbbetcdioiaozdjkvwxu.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiYmV0Y2Rpb2lhb3pkamt2d3h1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTM0NjQsImV4cCI6MjEwMTU4OTQ2NH0.GhV7HsGnAXA8Zb_IV3hxhwI9qmbM3qhcuWRMSXKUNcw'
);

async function testQuery() {
    console.log("Testing fetch profiles...");
    const { data, error } = await supabase
        .from('profiles')
        .select('id, display_name, full_name, iqama_number, phone_number, role')
        .limit(1);
    
    if (error) {
        console.error("Error:", error);
    } else {
        console.log("Success! Data:", data);
    }
}

testQuery();
