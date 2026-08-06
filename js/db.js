// IMPORTANT: Replace these with your actual Supabase Project URL and Anon Key
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';

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
    },

    // --- Authentication ---
    async login(email, password) {
        if (!supabaseClient) {
            console.warn("Mock Login Success");
            return { user: { email }, error: null };
        }
        
        try {
            const { data, error } = await supabaseClient.auth.signInWithPassword({
                email: email,
                password: password
            });
            return { user: data?.user, error };
        } catch (error) {
            return { user: null, error };
        }
    },

    async logout() {
        if (supabaseClient) {
            await supabaseClient.auth.signOut();
        }
    },

    async getUserProfile(userId) {
        if (!supabaseClient) {
            return { role: 'EMPLOYEE' }; // Mock fallback, email is not available here
        }

        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .select('role')
                .eq('id', userId)
                .single();
            
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching profile:", error.message);
            return { role: 'EMPLOYEE' }; // Default fallback
        }
    }
};
