const fs = require('fs');

const source = fs.readFileSync('js/db.js', 'utf8');
const urlMatch = source.match(/const SUPABASE_URL = '([^']+)'/);
const keyMatch = source.match(/const SUPABASE_ANON_KEY = '([^']+)'/);

if (!urlMatch || !keyMatch) {
    throw new Error('Unable to read the public Supabase client configuration.');
}

const baseUrl = urlMatch[1];
const anonKey = keyMatch[1];
const headers = {
    apikey: anonKey,
    Authorization: `Bearer ${anonKey}`,
    'Content-Type': 'application/json'
};

const checks = [
    ...['profiles', 'tasks', 'attendance', 'crm_deals', 'notifications', 'projects'].map(table => ({
        name: `table:${table}`,
        path: `/rest/v1/${table}?select=id&limit=1`,
        method: 'GET'
    })),
    {
        name: 'rpc:get_task_watcher_directory',
        path: '/rest/v1/rpc/get_task_watcher_directory',
        method: 'POST',
        body: '{}'
    }
];

const bucketChecks = ['task-attachments', 'contract-documents', 'crm-deal-files', 'hr-documents'];

Promise.all(checks.map(async check => {
    try {
        const response = await fetch(`${baseUrl}${check.path}`, {
            method: check.method,
            headers,
            body: check.body
        });
        const responseText = await response.text();
        let rows = 'n/a';
        try {
            const parsed = JSON.parse(responseText);
            if (Array.isArray(parsed)) rows = parsed.length;
        } catch (_) {
            // Only status and size are reported; response data is never printed.
        }
        console.log(`${check.name} status=${response.status} rows=${rows} bytes=${Buffer.byteLength(responseText)}`);
    } catch (error) {
        console.log(`${check.name} error=${error.message}`);
    }
})).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
});

Promise.all(bucketChecks.map(async bucket => {
    try {
        const response = await fetch(`${baseUrl}/storage/v1/bucket/${encodeURIComponent(bucket)}`, { headers });
        const responseText = await response.text();
        let visibility = 'not_disclosed';
        try {
            const parsed = JSON.parse(responseText);
            if (typeof parsed?.public === 'boolean') visibility = parsed.public ? 'public' : 'private';
        } catch (_) {
            // Bucket contents and metadata are never printed.
        }
        console.log(`bucket:${bucket} status=${response.status} visibility=${visibility}`);
    } catch (error) {
        console.log(`bucket:${bucket} error=${error.message}`);
    }
}));
