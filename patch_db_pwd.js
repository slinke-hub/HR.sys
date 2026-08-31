const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'js', 'db.js');
let content = fs.readFileSync(targetFile, 'utf8');

if (!content.includes('incrementPasswordChangeCount')) {
    // Add incrementPasswordChangeCount
    const newFunc = `
    async incrementPasswordChangeCount(userId) {
        if (!supabaseClient) return { success: false, error: new Error('Supabase not initialized') };
        try {
            // First get the current count
            const { data: profile, error: fetchError } = await supabaseClient
                .from('profiles')
                .select('password_changes_count')
                .eq('id', userId)
                .single();
            
            if (fetchError) throw fetchError;
            
            const currentCount = profile?.password_changes_count || 0;
            
            const { error: updateError } = await supabaseClient
                .from('profiles')
                .update({ password_changes_count: currentCount + 1 })
                .eq('id', userId);
                
            if (updateError) throw updateError;
            return { success: true };
        } catch (error) {
            console.error("incrementPasswordChangeCount Error:", error);
            return { success: false, error };
        }
    },`;
    
    // Insert before resetUserPassword
    content = content.replace('async resetUserPassword(userId, newPassword) {', newFunc + '\n\n    async resetUserPassword(userId, newPassword) {');
}

// Update resetUserPassword to also reset the count
if (!content.includes('password_changes_count: 0')) {
    const originalResetStr = `if (!data?.success) throw new Error(data?.error || 'Password reset failed');
            return { success: true };`;
    
    const newResetStr = `if (!data?.success) throw new Error(data?.error || 'Password reset failed');
            
            // Reset the password_changes_count on the profile
            const { error: profileError } = await supabaseClient
                .from('profiles')
                .update({ password_changes_count: 0 })
                .eq('id', userId);
            if (profileError) console.error("Failed to reset password_changes_count:", profileError);

            return { success: true };`;
            
    content = content.replace(originalResetStr, newResetStr);
}

fs.writeFileSync(targetFile, content, 'utf8');
console.log("Updated db.js for password limits.");
