# CRM Release 1A Recovery Procedure

Status: operator-reviewed draft. This is a forward-recovery guide, not an executable rollback plan.

## Release references

- Pre-release source baseline: `df351ebdad345bf11db20b933cec970d7098dd45` on `codex/production-crm-release-1a`.
- Verified Production rollback candidate: deployment `3iXVhhMKAxHANfbHv6TYboKLsjw`, immutable URL [https://hr-ndwggkkk1-montis-projects-b7e2f4fe.vercel.app](https://hr-ndwggkkk1-montis-projects-b7e2f4fe.vercel.app), Production domain [https://sys.muqam.net](https://sys.muqam.net), status Ready / Current, branch `main`, commit `df351eb`, deployed October 8, 2026. These details were verified by the administrator; re-verify the current Production deployment and confirm this candidate remains available immediately before release. Do not substitute the source commit for a deployment reference.
- Database compatibility evidence: use [CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql](CRM_RELEASE_1A_DATABASE_METADATA_QUERIES.sql) separately on staging and Production with an approved read-only role. The query file returns catalog metadata only; it does not inspect CRM/task business rows or change objects.
- Vercel access check for this review: the deployment reference above was supplied and verified by the administrator; this review did not access Vercel directly.
- Ordered database migrations: `20261022100000_crm_release_1a.sql`, `20261024100000_crm_mq20_contact_task_visibility.sql`, `20261026100000_mq20_task_service_authorization_hardening.sql`, and `20261027100000_task_dependency_visibility_hardening.sql`. Apply and record each as a separate version, in this order, after verifying the target and checksum. Each migration is transactional. The October 27, 2026 timestamp sorts after the other three; retain the filename and timestamp unchanged.
- This repository contains no CRM Release 1A down migration or approved SQL rollback artifact.

## Before release

1. Immediately before release, the release owner re-verifies the current Production deployment in Vercel, records its immutable URL/ID, and confirms deployment `3iXVhhMKAxHANfbHv6TYboKLsjw` remains available as the approved rollback candidate. If the current deployment or candidate differs from this record, update the recovery reference and reassess compatibility before proceeding.
2. The database operator confirms the target migration versions, function owners, and required task triggers against the approved baseline evidence. In particular, verify `enforce_private_task_list_ownership_trigger`, `enforce_task_completion_approval_trigger`, `validate_task_department_supervisor_trigger`, task activity/notification triggers, `crm_design_task_completion_trigger`, the CRM Release 1A `crm_deal_workflow_transition` trigger, `mq20_task_service_view_only`, and the `mq20_view_only_*` child-row triggers on task comments, attachments, dependencies, productivity history, and task lists.
3. Confirm the selected Vercel rollback target is compatible with the database state. The pre-release application may call CRM approval RPCs that Release 1A revokes, so an application-only rollback after the database migration commits is not assumed safe.
4. Ensure the operator has the approved database recovery procedure and a tested backup/restore path. Do not use this document as authorization to run a database restore.

## Application recovery

1. If the Release 1A application deployment fails before the database migration commits, pause the rollout and use Vercel's approved rollback/promotion control to restore immutable deployment `3iXVhhMKAxHANfbHv6TYboKLsjw` at `https://hr-ndwggkkk1-montis-projects-b7e2f4fe.vercel.app` to the Production domain. This restores application code only; it does not change database state.
2. If the migration has committed, first stop further rollout and determine the database state through the approved operator process. Do not immediately restore the old application: the new database revokes CRM approval mutation RPCs, and old application code may depend on them.
3. If the database is confirmed unchanged, restore deployment `3iXVhhMKAxHANfbHv6TYboKLsjw` (after confirming it is still the verified rollback candidate) to the Production domain and run the application recovery checks below. Application rollback does not reverse or alter database migrations.
4. If the database migration committed, keep the compatible Release 1A application available where possible and use a reviewed forward-fix migration. Restore the previous application only after the database operator has applied a reviewed compatibility repair that restores every required function definition, owner, grant, and trigger from the approved pre-release baseline.

## Database recovery options

- **Migration failed before commit:** each migration is wrapped in its own transaction. Stop before the next file, confirm the failed version is unapplied, and verify no partial DDL or data changes remain before retrying a corrected migration. Do not use migration repair to erase or rewrite historical versions.
- **Migration committed and behavior is defective:** prefer a new, reviewed forward migration. This release creates a generated-task identity ledger and tasks; reversing those records can lose idempotency or audit history.
- **Database restore is considered:** only the database operator may decide whether a point-in-time or backup restore is appropriate under the established recovery objectives. A restore can discard subsequent CRM, task, notification, and project changes. Coordinate its data-loss window and application compatibility before execution.
- **Function/trigger restoration:** no down migration is supplied. Use the exact pre-release definitions from approved baseline artifacts and restore owners, `SECURITY DEFINER` attributes, pinned search paths, EXECUTE grants/revocations, and trigger event definitions. The MQ-20 hardening migration replaces task access/manage/execute predicates, adds a ledger-backed Contact task visibility helper, and installs task/child-row view-only guards; a database recovery must account for all of these objects and the two MQ-20 comment/attachment SELECT policy expressions. Do not recreate old approval gates by hand or infer missing definitions from function names.

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
8. MQ-20 can read only an authorized Ines/MQ-08 task or their own ledger-backed Contact task; privileged RPCs cannot create or modify tasks, comments, attachments, dependencies, productivity history, or task lists as MQ-20.

## Stop conditions

Stop the rollout or recovery and escalate to the release owner and database operator if the current Production deployment or rollback candidate cannot be re-verified immediately before release; migration state is ambiguous; an expected function owner or task trigger is absent; the migration reports a partial or unexpected state; a CRM task has conflicting ledger identity; historical approval/audit data changed; authorization or financial checks fail; or Contact/Design task, notification, or My Day checks fail. Do not improvise a rollback or make direct production data edits to clear a stop condition.

## Known gaps before operational use

The Production rollback candidate is now recorded above, but its availability and the current Production deployment must be re-verified immediately before release. A complete safe, data-free Production-baseline schema is also unavailable here, so the full migration chain and database recovery steps have not been rehearsed. The release owner and database operator must resolve those gaps before staging or Production use. The catalog query plan is prepared, but results from staging and Production are still required for comparison; Production execution requires separate explicit approval.

Before staging evidence is collected, confirm the connection targets `jcfyyxsuspukcmybyhjj` using the approved connection inventory, run the catalog query in read-only mode, and retain only the metadata result sets. Run the identical query file against Production only after separate explicit approval. Compare trigger events/enabled state, function signatures/owners/security/search paths/EXECUTE rights, relevant columns/constraints, RLS/policies, and authorized migration-ledger versions; record every difference without querying business rows.
