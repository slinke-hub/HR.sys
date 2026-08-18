# Admin Password Reset Setup

The Users page now sends administrator-entered passwords to a protected Supabase Edge Function. The password is never returned to the browser, logged, or stored in the application database.

## Deploy once

1. In the Supabase SQL Editor, run `document_actions_and_admin_password_reset_migration.sql`.
2. Deploy the authenticated function:

   ```sh
   supabase functions deploy admin-set-user-password
   ```

3. Refresh the app so `js/app.js?v=6` and `js/db.js?v=6` are loaded.

Supabase automatically provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and the server-side secret/service key to deployed Edge Functions. Do not copy a service key into `js/db.js`, `index.html`, or any browser file.

The migration also enables document Edit/Delete permissions, blocks users from changing their own protected role fields, disables browser access to the legacy password-reset function, and stores password-reset audit metadata without storing passwords.
