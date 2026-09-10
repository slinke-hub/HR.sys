const { createClient } = require('@supabase/supabase-js');

async function test() {
    const supabaseUrl = process.env.MUQAM_SUPABASE_URL;
    const supabaseAnonKey = process.env.MUQAM_SUPABASE_ANON_KEY;
    const testEmail = process.env.MUQAM_TEST_USER_EMAIL;
    const testPassword = process.env.MUQAM_TEST_USER_PASSWORD;

    if (!supabaseUrl || !supabaseAnonKey || !testEmail || !testPassword) {
        throw new Error(
            'Missing required environment variables: MUQAM_SUPABASE_URL, '
            + 'MUQAM_SUPABASE_ANON_KEY, MUQAM_TEST_USER_EMAIL, and MUQAM_TEST_USER_PASSWORD.'
        );
    }

    if (process.env.MUQAM_ALLOW_ACCOUNT_CREATION_TEST !== 'yes') {
        throw new Error('Cloud user creation test is disabled. Set MUQAM_ALLOW_ACCOUNT_CREATION_TEST=yes for an intentional run.');
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey);
    const { data, error } = await supabase.rpc('create_user_by_admin', {
        new_email: testEmail,
        new_password: testPassword,
        new_role: 'EMPLOYEE',
        new_job_title: 'Tester',
        new_full_name: 'Test User',
        new_iqama: '1234567890',
        new_phone: '123456789',
        new_employee_id: 'EMP0001'
    });

    console.log('Data:', data);
    console.log('Error:', JSON.stringify(error, null, 2));
}

test().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});
