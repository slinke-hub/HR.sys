# Document expiry email automation

The daily worker updates document status using Riyadh's calendar date:

- `1–30` days left: `Expires Soon`
- `0` days or fewer: `Expired`
- More than `30` days: `Active`

It emails the owner and responsible person separately when a document first enters `Expires Soon`, and again when it becomes `Expired`. Successful deliveries are recorded so retries do not resend them.

## Setup

1. Run `document_tracker_migration.sql` in the Supabase SQL Editor if it has not already been applied.
2. Run `document_expiry_automation_migration.sql` in the Supabase SQL Editor.
3. Create a Resend API key and verify the domain used by the sender address.
4. Configure these Supabase Edge Function secrets:
   - `RESEND_API_KEY`
   - `DOCUMENT_EXPIRY_FROM_EMAIL` (`MUQAM HR <no-reply@muqam.net>`)
   - `DOCUMENT_EXPIRY_COMPANY_NAME` (optional; defaults to `MUQAM HR`)
   - `DOCUMENT_EXPIRY_CRON_SECRET` (a long random value)
5. Deploy `supabase/functions/document-expiry-notifier` with JWT verification disabled. The function still requires the private `x-cron-secret` header.
6. In the SQL Editor, open `document_expiry_cron_setup.sql`, replace its placeholder with the same cron secret without saving that value back to the file, and run it.

The scheduled job runs daily at 03:00 UTC, which is 06:00 in Riyadh.
