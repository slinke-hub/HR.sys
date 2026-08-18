-- Run this in the Supabase SQL Editor after deploying document-expiry-notifier.
-- Replace the placeholder only in the SQL Editor. Do not save a real secret in this file.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

SELECT vault.create_secret(
    'https://bbbetcdioiaozdjkvwxu.supabase.co',
    'document_expiry_project_url'
);

SELECT vault.create_secret(
    'REPLACE_WITH_THE_SAME_DOCUMENT_EXPIRY_CRON_SECRET',
    'document_expiry_cron_secret'
);

-- Runs every day at 03:00 UTC / 06:00 Asia/Riyadh.
SELECT cron.schedule(
    'document-expiry-daily',
    '0 3 * * *',
    $$
    SELECT net.http_post(
        url := (
            SELECT decrypted_secret
            FROM vault.decrypted_secrets
            WHERE name = 'document_expiry_project_url'
        ) || '/functions/v1/document-expiry-notifier',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-cron-secret', (
                SELECT decrypted_secret
                FROM vault.decrypted_secrets
                WHERE name = 'document_expiry_cron_secret'
            )
        ),
        body := '{}'::jsonb
    ) AS request_id;
    $$
);
