# Security policy

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Send the report privately to the system owner and include the affected page or function, reproduction steps, impact, and any relevant logs with credentials removed.

Do not include passwords, access tokens, private keys, employee documents, or production records in screenshots, issues, commits, chat messages, or test fixtures.

## Secret handling

- Keep local secrets in `.env` or Supabase Edge Function secrets. The repository must contain placeholders only.
- The browser may contain only the Supabase public anonymous key. Service-role keys, Resend keys, VAPID private keys, dispatch secrets, passwords, and Android signing keys must never be shipped to the browser or committed.
- Use a unique password for every account. Bulk employee imports require an explicit temporary password of at least 12 characters for each employee.
- Rotate a credential immediately if it is exposed, then remove it from Git history. Deleting it only from the latest commit is not sufficient.

## Required production controls

1. Apply all Supabase migrations in order and deploy the Edge Functions from this repository.
2. Configure `TASK_EMAIL_DISPATCH_SECRET`, `PUSH_DISPATCH_SECRET`, `DOCUMENT_EXPIRY_CRON_SECRET`, email-provider secrets, and VAPID keys in the deployment secret store.
3. Keep Supabase Row Level Security enabled and run `npm run security:check` before release.
4. Require MFA for Supabase, GitHub, Vercel, and administrator accounts. Protect the default branch with pull-request review and passing security checks.
5. Restrict production logs to authorized administrators and never log authorization headers, passwords, tokens, or uploaded document contents.

## Incident response

If compromise is suspected: disable the affected account or key, revoke active sessions, rotate secrets, preserve audit logs, review database and storage access, patch the root cause, and notify affected people as required by applicable policy or law.
