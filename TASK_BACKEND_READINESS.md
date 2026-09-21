# HR.sys Task Backend Mobile Readiness

## Scope

This run covers Task Manager only. Deals, Projects, Clients, Notifications, and React Native were not implemented here.

## Implemented authoritative operations

The web adapter now uses secure Supabase RPCs for task listing/detail, creation, updates, deletion, comments, attachment metadata, attachment listing/removal, and activity history. Assignment and status transitions continue to use the existing `assign_task` and `change_task_status` RPCs. Completion and reopen are shared-service aliases over the same status RPC.

The database migration adds task-scoped access predicates, comment RPCs, attachment registration/list/removal RPCs, activity history and triggers, private storage write policies, and removes the legacy globally-readable task comment/attachment policies. Existing MQ-20 restrictions and task-list/department rules are preserved.

## Verification

- Static task façade and threat-matrix checks pass.
- JavaScript syntax checks pass.
- Shared TypeScript contracts bundle successfully.
- Existing security hardening, task completion, CRM regression, and presentation workflow tests pass.
- Mobile web bundle builds successfully.

Migrations `20260917090000` and `20260917110000` were applied to the linked project `bbbetcdioiaozdjkvwxu` in order and are both present in remote migration history.

Live RPC privilege checks confirm all Task RPCs are executable by `authenticated` and not by `anon`; all four Task tables have RLS enabled. Rollback-only authenticated workflow, assignee-guard, and private-task IDOR/direct-table bypass probes passed, and all probe records were rolled back (remote count: 0). Anonymous REST/RPC probes reject protected Task operations. The local Task Manager shell and authoritative Task service assets return HTTP 200; full browser interaction still requires an application test account.

## Current decision

`TASK BACKEND MOBILE READINESS: READY`

Remaining operational risks: a local database dump/recovery snapshot could not be created because Docker/Podman is unavailable, and authenticated browser UI automation would require a dedicated test account.
