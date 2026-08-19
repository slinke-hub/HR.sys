const fs = require('fs');

let dbJs = fs.readFileSync('e:/HR.sys/js/db.js', 'utf8');

// Update fetchRequests
const fetchReqTarget = `    async fetchRequests(userId = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('requests').select('*, profiles(full_name)').order('created_at', { ascending: false });
            if (userId) {
                query = query.eq('employee_id', userId);
            }
            const { data, error } = await query;
            if (error) throw error;
            return data;
        } catch (error) {
            console.error("Error fetching requests:", error);
            return [];
        }
    },`;

const fetchReqReplacement = `    async fetchRequests(userObj = null) {
        if (!supabaseClient) return [];
        try {
            let query = supabaseClient.from('requests').select('*, profiles!requests_employee_id_fkey(full_name, manager_id)').order('created_at', { ascending: false });
            
            let userId = null;
            let role = null;
            if (typeof userObj === 'object' && userObj !== null) {
                userId = userObj.id;
                role = userObj.role;
            } else if (typeof userObj === 'string') {
                userId = userObj;
                role = 'EMPLOYEE';
            }

            // Only employees are hard-filtered at the DB query level to save bandwidth
            if (role === 'EMPLOYEE' && userId) {
                query = query.eq('employee_id', userId);
            }

            const { data, error } = await query;
            if (error) throw error;

            if (role === 'MANAGER' && userId) {
                return data.filter(req => req.employee_id === userId || (req.profiles && req.profiles.manager_id === userId));
            }

            return data;
        } catch (error) {
            console.error("Error fetching requests:", error);
            return [];
        }
    },`;

dbJs = dbJs.replace(fetchReqTarget, fetchReqReplacement);
fs.writeFileSync('e:/HR.sys/js/db.js', dbJs, 'utf8');

let appJs = fs.readFileSync('e:/HR.sys/js/app.js', 'utf8');

const appReqTarget = `const requests = await db.fetchRequests(isEmployee ? currentUser?.id : null);`;
const appReqReplacement = `const requests = await db.fetchRequests(currentUser);`;

appJs = appJs.replace(appReqTarget, appReqReplacement);
fs.writeFileSync('e:/HR.sys/js/app.js', appJs, 'utf8');

console.log("Updated requests logic to route requests to department managers.");
