const fs = require('fs');
let dbJs = fs.readFileSync('js/db.js', 'utf8');

const insertCode = `
    async fetchReleasedPayslips(monthYear) {
        if (!supabaseClient) return [];
        try {
            const { data, error } = await supabaseClient.from('released_payslips').select('*').eq('month_year', monthYear).order('created_at', { ascending: false });
            if (error) throw error;
            return data || [];
        } catch (error) {
            console.error("fetchReleasedPayslips Error:", error);
            return [];
        }
    },
    async saveReleasedPayslips(payslipsArray) {
        if (!supabaseClient) return { success: false };
        try {
            const { error } = await supabaseClient.from('released_payslips').insert(payslipsArray);
            if (error) throw error;
            return { success: true };
        } catch (error) {
            console.error("saveReleasedPayslips Error:", error);
            return { success: false, error };
        }
    },
`;

dbJs = dbJs.replace('async fetchPayrollAdjustments(monthYear) {', insertCode + '    async fetchPayrollAdjustments(monthYear) {');
fs.writeFileSync('js/db.js', dbJs);
console.log('Success');
