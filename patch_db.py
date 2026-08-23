import sys

filename = r'e:\HR.sys\js\db.js'
with open(filename, 'r', encoding='utf-8') as f:
    content = f.read()

new_methods = '''
    // Translation API
    async fetchSystemTranslations() {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient.from('system_translations').select('*');
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching system translations:", error);
            return [];
        }
    },
    async saveSystemTranslation(key, transEn, transAr) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { data, error } = await supabaseClient
                .from('system_translations')
                .upsert({ trans_key: key, trans_en: transEn, trans_ar: transAr, updated_at: new Date().toISOString() })
                .select();
            if (error) throw error;
            return { success: true, data };
        } catch (error) {
            console.error("Error saving system translation:", error);
            return { success: false, error };
        }
    },
    async deleteSystemTranslation(key) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { error } = await supabaseClient
                .from('system_translations')
                .delete()
                .eq('trans_key', key);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("Error deleting system translation:", error);
            return { success: false, error };
        }
    },
    subscribeToTranslations(callback) {
        if (!supabaseClient) return null;
        const channel = supabaseClient.channel('system_translations_changes')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'system_translations' }, payload => {
                callback(payload);
            })
            .subscribe();
        return channel;
    },

    // User Management API'''

content = content.replace('    // User Management API', new_methods)

with open(filename, 'w', encoding='utf-8') as f:
    f.write(content)

print('Patched db.js')
