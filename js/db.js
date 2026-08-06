// IMPORTANT: Replace these with your actual Supabase Project URL and Anon Key
const SUPABASE_URL = 'https://bbbetcdioiaozdjkvwxu.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJiYmV0Y2Rpb2lhb3pkamt2d3h1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYwMTM0NjQsImV4cCI6MjEwMTU4OTQ2NH0.GhV7HsGnAXA8Zb_IV3hxhwI9qmbM3qhcuWRMSXKUNcw';

// Initialize the Supabase client
// This uses the global supabase object loaded via the CDN in index.html
let supabaseClient = null;

if (SUPABASE_URL !== 'YOUR_SUPABASE_URL' && SUPABASE_ANON_KEY !== 'YOUR_SUPABASE_ANON_KEY') {
    supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    console.log("Supabase client initialized successfully.");
} else {
    console.warn("Supabase credentials not configured. Using mocked data/actions.");
}

// Global DB helper functions for the prototype
const db = {
    async clockIn() {
        if (!supabaseClient) {
            console.log("Mock: Clocked in (Supabase not configured)");
            return true;
        }

        try {
            const { data, error } = await supabaseClient
                .from('time_punches')
                .insert([
                    { punch_type: 'IN', employee_id: '00000000-0000-0000-0000-000000000000' } // Dummy UUID for prototype
                ]);

            if (error) throw error;
            return true;
        } catch (error) {
            console.error("Error clocking in:", error.message);
            return false;
        }
    },

    async fetchAnnouncements() {
        if (!supabaseClient) {
            return null; // Return null to fallback to mocked data in app.js
        }

        try {
            const { data, error } = await supabaseClient
                .from('announcements')
                .select('*')
                .order('created_at', { ascending: false });

            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching announcements:", error.message);
            return null;
        }
    }
};
