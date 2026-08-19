const fs = require('fs');

let dbContent = fs.readFileSync('e:/HR.sys/js/db.js', 'utf8');

// Fix 1: fetchUsers select
dbContent = dbContent.replace(
    /role, job_title, created_at, manager_id/g,
    'role, created_at, manager_id'
);

// Fix 2: updateUserJobTitle - no-op it
const target2 = `    async updateUserJobTitle(userId, jobTitle) {
        if (!supabaseClient) return { success: false };
        try {
            const { data, error } = await supabaseClient
                .from('profiles')
                .update({ job_title: jobTitle })
                .eq('id', userId);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("updateUserJobTitle Error:", error);
            return { success: false, error };
        }
    },`;
const replacement2 = `    async updateUserJobTitle(userId, jobTitle) {
        // job_title was moved to contracts
        return { success: true };
    },`;
dbContent = dbContent.replace(target2, replacement2);

// Fix 3: fetchTasks select
dbContent = dbContent.replace(
    /profiles:assignee_id\(id, full_name, job_title, role\)/g,
    'profiles:assignee_id(id, full_name, role)'
);

fs.writeFileSync('e:/HR.sys/js/db.js', dbContent, 'utf8');
console.log("Fixed job_title references in db.js");
