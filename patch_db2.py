import sys

filename = r'e:\HR.sys\js\db.js'
with open(filename, 'r', encoding='utf-8') as f:
    content = f.read()

new_method = '''    async saveSystemTranslationsBatch(translationsArray) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            const { data, error } = await supabaseClient
                .from('system_translations')
                .upsert(translationsArray.map(t => ({...t, updated_at: new Date().toISOString()})))
                .select();
            if (error) throw error;
            return { success: true, data };
        } catch (error) {
            console.error("Error saving system translations batch:", error);
            return { success: false, error };
        }
    },
    async deleteSystemTranslation(key) {'''

content = content.replace("    async deleteSystemTranslation(key) {", new_method)

with open(filename, 'w', encoding='utf-8') as f:
    f.write(content)

print('Patched db.js successfully')
