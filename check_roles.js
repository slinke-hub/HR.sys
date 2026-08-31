require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY);
(async () => {
    const { data, error } = await supabase.from('profiles').select('id, full_name, email, role, job_title');
    if (error) console.error(error);
    else console.log(data.map(d => `${d.email}: role='${d.role}', job='${d.job_title}'`).join('\n'));
})();
