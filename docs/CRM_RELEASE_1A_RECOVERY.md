# CRM Release 1A Recovery Procedure

Status: operator-reviewed draft. This is a forward-recovery guide, not an executable rollback plan.

## Release references

- Pre-release source baseline: `df351ebdad345bf11db20b933cec970d7098dd45` on `codex/production-crm-release-1a`.
- Previous Production Vercel deployment: **not found in the checked-in release evidence**. Before release, record the immutable Production deployment URL and deployment ID from the Vercel project’s deployment history. Do not substitute the source commit for a deployment reference.
- Database compatibility evidence: use [CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql](CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql) separately on staging and Production with an approved read-only role. The query file returns catalog metadata only; it does not inspect CRM/task business rows or change objects.
- Vercel access check for this review: no Vercel deployment connector, Vercel CLI, or local Vercel project link was available. The prior deployment was not looked up through another account or secret source.
- Database migration: `20261022100000_crm_release_1a.sql`.
- This repository contains no CRM Release 1A down migration or approved SQL rollback artifact.

## Before release

1. The release owner records the last-known-good Vercel Production deployment URL/ID and confirms it is still available for promotion.
2. The database operator confirms the target migration version, function owners, and required task triggers against the approved Production baseline evidence. In particular, verify `enforce_private_task_list_ownership_trigger`, `enforce_task_completion_approval_trigger`, `validate_task_department_supervisor_trigger`, task activity/notification triggers, `crm_design_task_completion_trigger`, and the CRM Release 1A `crm_deal_workflow_transition` trigger.
3. Confirm the selected Vercel rollback target is compatible with the database state. The pre-release application may call CRM approval RPCs that Release 1A revokes, so an application-only rollback after the database migration commits is not assumed safe.
4. Ensure the operator has the approved database recovery procedure and a tested backup/restore path. Do not use this document as authorization to run a database restore.

## Application recovery

1. If the Release 1A application deployment fails before the database migration commits, pause the rollout and use the recorded immutable last-known-good Vercel Production deployment to restore the prior application.
2. If the migration has committed, first stop further rollout and determine the database state through the approved operator process. Do not immediately restore the old application: the new database revokes CRM approval mutation RPCs, and old application code may depend on them.
3. If the database is confirmed unchanged, restore the recorded previous Vercel deployment and run the application recovery checks below.
4. If the database migration committed, keep the compatible Release 1A application available where possible and use a reviewed forward-fix migration. Restore the previous application only after the database operator has applied a reviewed compatibility repair that restores every required function definition, owner, grant, and trigger from the approved pre-release baseline.

## Database recovery options

- **Migration failed before commit:** the migration is wrapped in a transaction. Confirm the database reports the migration as unapplied and verify no partial DDL or data changes remain before retrying a corrected migration.
- **Migration committed and behavior is defective:** prefer a new, reviewed forward migration. This release creates a generated-task identity ledger and tasks; reversing those records can lose idempotency or audit history.
- **Database restore is considered:** only the database operator may decide whether a point-in-time or backup restore is appropriate under the established recovery objectives. A restore can discard subsequent CRM, task, notification, and project changes. Coordinate its data-loss window and application compatibility before execution.
- **Function/trigger restoration:** no down migration is supplied. Use the exact pre-release definitions from the approved baseline artifacts and restore owners, `SECURITY DEFINER` attributes, pinned search paths, EXECUTE grants/revocations, and trigger event definitions. Do not recreate old approval gates by hand or infer missing definitions from function names.

## Release 1A task and history handling

- Keep tasks created with `CONTACT_DISCUSSION` and `QUOTE_PROPOSAL_DESIGN` and their rows in `crm_generated_tasks`. Do not delete or detach them as a rollback shortcut. Re-entry relies on that durable identity to avoid duplicate tasks.
- Preserve CRM deals and their stage/history, `crm_deal_approval_steps`, `crm_design_task_approval_steps`, task activity, CRM deal activity, and notifications. The migration is intended to retain historical approval records while retiring their gates.
- Do not reset Design task status, due dates, assignees, submission links, or completed status during recovery. Use a separately reviewed repair if an individual task needs correction.

## Recovery verification

After a recovery action, verify against a disposable database or approved read-only evidence first. Confirm:

1. The application points to the intended deployment and loads without stale cached assets.
2. CRM role authorization, document checks, financial authorization, contractual validation, and deal ownership checks behave as expected.
3. The CRM stage trigger blocks new Discussion transitions while allowing historical records to remain readable.
4. Direct premature Won RPC calls fail; valid Presentation submission and order progression follow the intended workflow.
5. Contact and Design tasks retain one-per-deal identity, authorization, assignees, due dates, completion status, activity history, and notifications.
6. Task Manager and My Day visibility and action permissions still follow the established assignee, list, department, and manager rules.
7. Historical CRM approvals, deals, activity, and notifications remain present and unchanged.

## Stop conditions

Stop the rollout or recovery and escalate to the release owner and database operator if the previous Vercel deployment reference is unavailable; migration state is ambiguous; an expected function owner or task trigger is absent; the migration reports a partial or unexpected state; a CRM task has conflicting ledger identity; historical approval/audit data changed; authorization or financial checks fail; or Contact/Design task, notification, or My Day checks fail. Do not improvise a rollback or make direct production data edits to clear a stop condition.

## Known gaps before operational use

The immutable previous Production Vercel deployment URL/ID is not recorded in this repository. A complete safe, data-free Production-baseline schema is also unavailable here, so the full migration chain and database recovery steps have not been rehearsed. The release owner and database operator must resolve those gaps before staging or Production use. The catalog query plan is prepared, but results from staging and Production are still required for comparison; Production execution requires separate explicit approval.

Before staging evidence is collected, confirm the connection targets `jcfyyxsuspukcmybyhjj` using the approved connection inventory, run the catalog query in read-only mode, and retain only the metadata result sets. Run the identical query file against Production only after separate explicit approval. Compare trigger events/enabled state, function signatures/owners/security/search paths/EXECUTE rights, relevant columns/constraints, RLS/policies, and authorized migration-ledger versions; record every difference without querying business rows.
