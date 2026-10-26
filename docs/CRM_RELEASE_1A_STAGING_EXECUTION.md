# HR.sys CRM Release 1A staging execution package

This package is prepared for DBA review. It has not connected to staging or run any migration. The runner defaults to a read-only preflight; its `-Execute` path requires a separate administrator approval, typed confirmations, and the full SHA of an independently reviewed immutable Git commit.

## Fixed scope

Target: Supabase project `jcfyyxsuspukcmybyhjj`, host `db.jcfyyxsuspukcmybyhjj.supabase.co`, database `postgres`, role `postgres`, PostgreSQL 17.6. Production project `bbbetcdioiaozdjkvwxu` is rejected by the runner.

Documented Production application rollback candidate: deployment `3iXVhhMKAxHANfbHv6TYboKLsjw`, immutable URL [https://hr-ndwggkkk1-montis-projects-b7e2f4fe.vercel.app](https://hr-ndwggkkk1-montis-projects-b7e2f4fe.vercel.app), Production domain [https://sys.muqam.net](https://sys.muqam.net). Re-verify its current status and availability immediately before release; application rollback does not reverse database migrations.

The runner applies only these four committed files, in this order, after verifying their pinned SHA-256 checksums:

1. `20261022100000_crm_release_1a.sql`
2. `20261024100000_crm_mq20_contact_task_visibility.sql`
3. `20261026100000_mq20_task_service_authorization_hardening.sql`
4. `20261027100000_task_dependency_visibility_hardening.sql`

The October 27 timestamp is retained and sorts last. The historical `20260830000000_initial_schema` entry and the three October security migration records are prerequisites; the data-bearing initial-schema SQL is intentionally absent and must not be replayed. No broad migration command is used.

## Before an approved execution session

1. Obtain a fresh DBA authorization reference and verify the staging project, database, effective role, PostgreSQL version, complete migration-version inventory, and TLS connection from the authorized operator.
2. Obtain the CA PEM bundle from a trusted Supabase source through the administrator’s approved channel. Verify its SHA-256 fingerprint independently. Do not place credentials in a URL, file, shell argument, or chat.
3. In PowerShell 7, from this workspace, run the runner without `-Execute` first. It connects to the hard-coded staging hostname using `sslmode=verify-full`, prompts for the password without echoing it, checks server identity/TLS/schema/RLS/history, and exits without writes:

   ```powershell
   .\scripts\crm-release-1a-staging.ps1 `
     -ProjectRef jcfyyxsuspukcmybyhjj `
     -CaFile 'C:\approved\path\staging-ca.pem'
   ```

4. Review the full read-only report and confirm the four historical/security versions are present and all four Release 1A versions are absent. Any mismatch is a stop condition.
5. Before execution, independently review and record the full Git commit SHA containing the approved runner package. Execution requires `-ApprovedCommit` to equal `HEAD` exactly, rejects any tracked/index changes or relevant untracked execution files, and verifies every critical package file against that commit's Git blob. The commit SHA is the trust anchor; no editable local manifest can authorize its own changes. The runner copies verified SQL bytes into a unique temporary snapshot, keeps each snapshot write-locked while in use, and executes only those snapshots. It rechecks the anchored package at every migration, postcheck, and ledger checkpoint; any change stops further work.

   Only after separate written DBA approval, run execution mode with both the approval reference and independently reviewed commit SHA. The runner displays the CA bundle fingerprint and demands its exact confirmation, plus separate exact confirmations for the approved commit, the overall release, each migration, and each ledger update. It prompts for a hidden password separately for every `psql` connection and for the CLI ledger step. Credentials are held in process memory/environment only for the child CLI call and restored in `finally`.

   ```powershell
   .\scripts\crm-release-1a-staging.ps1 `
     -ProjectRef jcfyyxsuspukcmybyhjj `
     -CaFile 'C:\approved\path\staging-ca.pem' `
     -Execute `
     -ApprovalReference '<DBA approval reference>' `
     -ApprovedCommit '<full independently reviewed Git commit SHA>'
   ```

Do not invoke the execution command until that separate approval exists. The application Preview and its staging authentication issue are separate release gates; migration readiness alone does not authorize application deployment.

## Per-migration checkpoints

For each file, the runner verifies the exact hash and transaction boundary, verifies that the ledger is unchanged, then calls `psql -X -W -v ON_ERROR_STOP=1 -d <fixed staging TLS URI> -f <exact migration path>`. Each migration retains its own `BEGIN`/`COMMIT`. It next runs the read-only assertions in `CRM_RELEASE_1A_STAGING_POSTCHECKS.sql`. Only if SQL and catalog checks succeed does it request a separate confirmation and invoke Supabase CLI `migration repair <version> --status applied --db-url <same fixed staging TLS URI>`. It checks that the entire prior version/name inventory is unchanged and exactly the one approved version was added before offering the next file.

The script also runs the existing read-only metadata query after the fourth checkpoint. The preflight and postcheck SQL files return catalog/identity metadata only; they do not inspect employee, task, or CRM records. The postcheck verifies cumulative CRM, Contact visibility, MQ-20 guard, dependency/activity policies, function ownership/security settings, and effective grants. For the CLI ledger child process, `PGSSLMODE=verify-full` and `PGSSLROOTCERT` are set explicitly and restored afterward so TLS verification remains enforced even if the CLI rebuilds its connection URL.

## Stop and recovery rules

- Wrong project ref, link, branch/HEAD, checksum, CA, database, role, server version, TLS state, prerequisite object, ledger row, grant, policy, trigger, or function setting: stop before the next operation.
- Any SQL/CLI error, disconnect, or ambiguous result: do not retry the migration or ledger write. Reconnect read-only and have the DBA reconcile catalog state and migration history first.
- Error before a confirmed transaction commit: the file’s transaction should roll back on connection loss; verify this read-only rather than assuming it.
- SQL committed but a postcheck failed: leave the schema in place, do not record the version, do not replay the file, and request DBA review for a forward-only correction.
- Postchecks passed but ledger recording failed or its outcome is uncertain: do not rerun SQL. Verify exact catalog state and ledger state read-only. A separately reviewed, version-specific `migration repair --status applied` is allowed only after the DBA confirms the committed schema is complete. Never repair or remove historical versions.
- A partial sequence is not resumable by this initial runner. Preserve completed migrations and their history; stop and obtain a reviewed continuation/forward-recovery plan for the remaining exact files.
- Preserve CRM deals, historical approvals, notifications, audit/activity history, existing tasks, and newly generated tasks. Recovery is forward-only for database state. Application rollback to the separately verified immutable Production deployment does not roll back database changes.

No rollback, migration, ledger write, staging connection, or deployment has been performed while preparing this package.
