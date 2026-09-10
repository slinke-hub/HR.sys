# MUQAM HR Defensive Security Audit

Date: 2026-09-10  
Scope: `sys.muqam.net`, the local MUQAM HR web project, its public Supabase client surface, and listening TCP services on the development workstation.  
Method: non-destructive browser verification, limited common-port checks, HTTP response checks, anonymous API authorization checks, dependency review, and static source/migration review.

## Executive summary

The production hostname exposed only the expected web ports (80 and 443) during the limited remote scan. Port 80 correctly redirects to HTTPS. Common remote-access, database, cache, and development ports tested against the production hostname were closed or filtered.

Two critical application exposures were found:

1. The production deployment serves repository-only files, including an account-creation helper and SQL migrations. The deployed helper contains a plaintext credential from an earlier version.
2. Legacy storage migrations mark HR contracts, task attachments, and CRM deal files as public, which can bypass row-level read policies for anyone holding an object URL.

The codebase has been hardened locally, but the production exposure remains active until these changes are deployed. The exposed password must be rotated because deleting it from the current files cannot remove copies from caches or Git history.

## Findings and remediation

### Critical — repository files published by the production deployment

Evidence: the live hostname returned HTTP 200 for the account-creation helper and a SQL migration, while `.env`, `.git/config`, and `package.json` returned 404.

Remediation implemented:

- Added `vercel.json` with `npm run mobile:web` as the build and `www` as the only deployment output.
- The build script already copies only the app HTML, service worker, manifest, CSS, images, JavaScript, and templates into `www`.
- Verified the hardened local server returns 404 for the helper, SQL migrations, package manifest, Git metadata, and encoded traversal attempts.

Required operational action: deploy the current changes immediately, then verify the previously exposed paths return 404.

### Critical — plaintext account credential in a tracked helper

Evidence: `create_admin.js` contained a real-looking email and plaintext password.

Remediation implemented:

- Removed embedded account values.
- Required environment variables for all account inputs.
- Added an explicit `MUQAM_ALLOW_ACCOUNT_CREATION=yes` safety gate.
- Applied the same safeguards to `test_create_user.js`.
- Added `.env` files to `.gitignore` and provided a placeholder-only `.env.example`.

Required operational action: rotate the exposed password, revoke active sessions for that account, and review authentication logs. Consider removing the secret from Git history in a coordinated maintenance window.

### Critical — sensitive storage buckets configured as public

Evidence: legacy SQL explicitly configured `contract-documents`, `task-attachments`, and `crm-deal-files` as public buckets and the frontend generated permanent public URLs.

Remediation implemented:

- Added a migration that makes task, contract, CRM, and legacy HR-document buckets private.
- Replaced permanent public URLs with `storage://` references and one-hour signed URLs generated only after authorization.
- Added read policies for CRM-authorized users, contract owners/managers, and users who can read the related task.
- Restricted CRM attachment uploads to authenticated CRM users.
- Added compatibility handling for existing public URL records so they are converted to signed URLs after the buckets become private.

Required operational action: apply `20260910123500_private_sensitive_storage.sql` to the linked Supabase project.

### High — development server exposed the repository and LAN interface

Evidence: the previous `serve` command served the repository root on `0.0.0.0:3000` by default.

Remediation implemented:

- Replaced the third-party server with `scripts/serve-local.mjs`.
- It binds only to `127.0.0.1:4173`.
- It serves only `www`, rejects dotfiles and traversal, permits only GET/HEAD, and returns 405 for other methods.
- Verified the listener is `127.0.0.1:4173`, not `0.0.0.0`.

### High — unsafe dynamic HTML and URL handling

Evidence: toast and field-error messages were inserted into HTML without escaping, and an externally supplied map URL was HTML-escaped but not scheme-validated.

Remediation implemented:

- Escaped dynamic toast and field-error text.
- Added an HTTP/HTTPS-only URL validator.
- Added `noopener noreferrer` to external map links.
- Applied URL validation to resolved task attachment links.

Residual risk: the legacy frontend still contains many `innerHTML` assignments and inline event handlers. A future refactor should remove inline handlers and adopt a nonce-based CSP or Trusted Types before removing CSP `unsafe-inline`.

### High — anonymous execution of privileged database functions

Evidence: migration review showed privileged functions use safe fixed search paths, but PostgreSQL grants function execution to `PUBLIC` by default unless explicitly revoked.

Remediation implemented:

- Added `20260910123000_revoke_anonymous_security_definer_execution.sql` to revoke privileged function execution from `PUBLIC` and `anon`, while preserving authenticated and service access.

Live verification: the anonymous employee-directory RPC returned HTTP 401. Anonymous reads of profiles, tasks, attendance, CRM deals, notifications, and projects returned zero rows.

### Medium — missing browser security headers

Evidence: production returned HSTS but did not return CSP, clickjacking protection, MIME-sniffing protection, Referrer Policy, Permissions Policy, COOP, or CORP headers.

Remediation implemented:

- Added CSP, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, Referrer Policy, Permissions Policy, COOP, and CORP to the Vercel deployment.
- Allowed camera and geolocation only for the same origin because attendance features require them.
- Added equivalent headers to the local server.
- Added no-cache handling for the service worker and HTML shell.

### Medium — dependency exposure

Remediation implemented:

- Removed the vulnerable third-party local server.
- Removed an unused linter that pulled high-severity advisories into the dependency graph.
- Moved development-only tooling out of production dependencies.

Verification: the production dependency audit reports zero known vulnerabilities. Three moderate advisories remain in Capacitor CLI's mobile build-only dependency chain, with no upstream fix currently available.

## Port results

Production hostname:

- Open: 80 (HTTP redirect only), 443 (HTTPS application).
- Closed or filtered in the limited scan: 21, 22, 23, 25, 445, 1433, 3000, 3306, 5432, 6379, 7070, 8080, 8443.

Development workstation:

- MUQAM HR hardened server: `127.0.0.1:4173` only.
- Unrelated Node application: `0.0.0.0:3000`.
- AnyDesk: `0.0.0.0:7070`.

The unrelated Node and AnyDesk listeners were not stopped because they are outside the MUQAM HR project and may be intentional. Their external reachability depends on Windows Firewall and network configuration. Disable them when not needed or explicitly restrict them to trusted networks.

## Verification completed

- Hardened MUQAM login and CRM pages loaded successfully in the in-app browser.
- Security regression test passed.
- JavaScript syntax checks passed.
- Production dependency audit: 0 known vulnerabilities.
- Local sensitive-file and traversal requests: 404.
- Local unsupported HTTP method: 405.
- Anonymous database table checks: 0 rows.
- Anonymous employee-directory RPC: 401.
- Remote common-port scan: only 80 and 443 open.

## Remaining actions before calling the production system hardened

1. Deploy the current repository so Vercel publishes only `www` and applies the security headers.
2. Rotate the exposed account password and revoke existing sessions.
3. Apply both new Supabase migrations.
4. Verify the exposed production paths now return 404 and sensitive storage URLs require signed access.
5. Review whether the unrelated workstation listeners on ports 3000 and 7070 are needed.

No finite audit can guarantee that a system is fully secure. These controls close the verified exposures in this scope and substantially reduce credential, file-disclosure, browser-injection, and development-server risk.
