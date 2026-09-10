const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.MUQAM_SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.MUQAM_SUPABASE_ANON_KEY;
const ADMIN_EMAIL = process.env.MUQAM_ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.MUQAM_ADMIN_PASSWORD;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !ADMIN_EMAIL || !ADMIN_PASSWORD) {
    throw new Error(
        'Missing required environment variables: MUQAM_SUPABASE_URL, '
        + 'MUQAM_SUPABASE_ANON_KEY, MUQAM_ADMIN_EMAIL, and MUQAM_ADMIN_PASSWORD.'
    );
}

if (process.env.MUQAM_ALLOW_ACCOUNT_CREATION !== 'yes') {
    throw new Error('Account creation is disabled. Set MUQAM_ALLOW_ACCOUNT_CREATION=yes for an intentional one-time run.');
}

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function main() {
    console.log('Signing up the configured user...');
    const { data, error } = await supabase.auth.signUp({
        email: ADMIN_EMAIL,
        password: ADMIN_PASSWORD
    });

    if (error) {
        console.error('Error:', error.message);
        if (error.message.includes('already registered')) {
            console.log('User is already registered.');
        }
    } else {
        console.log('Success! User ID:', data.user?.id);
    }
}

main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
});
