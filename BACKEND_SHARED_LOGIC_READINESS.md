# Backend & Shared Business Logic Readiness

Date: 2026-09-17

This phase prepares HR.sys for a future React Native client. It does not create
the mobile application, remove Capacitor, or migrate away from Supabase.

## Target architecture

```text
HR.sys Web ───────────────┐
                          ▼
                Shared HR.sys services/API
                          │
                          ▼
              Supabase Auth + PostgreSQL
              RLS + RPCs + triggers + Storage
                          ▲
                          │
React Native iOS/Android ─┘
```

The database remains the source of truth. A client-side service bridge is
provided for reuse, but it is not a security boundary; authorization remains in
RLS and server-side functions.

## Business logic location matrix

| Operation | Current Location | Server Enforced? | Safe for Mobile? | Recommended Location | Refactor Required |
|---|---|---:|---:|---|---|
| Create task | Web form + `db.createTask` + task defaults/RLS | Partial | No | Task API/RPC + RLS | Yes |
| Update task fields | Web form + direct table update + RLS | Partial | No | Task API/RPC + RLS | Yes |
| Assign task | `assign_task` RPC + task access policies | Yes for assignment | Yes, via RPC | Assignment service | Complete for assignment path |
| Change task status | `change_task_status` RPC + completion triggers | Yes | Yes, via RPC | Task status RPC | Complete for this path |
| Delete task | Web client + RLS/history cleanup trigger | Partial | No | Protected delete RPC | Yes |
| Add task comment | Web client + `task_comments` RLS/trigger | Partial | No | Comment service/API | Yes |
| Attach task/comment file | Storage + attachment table + RLS | Partial | No | Signed upload service | Yes |
| Deal create/update | Web client + CRM RLS | Partial | No | Deal service/API | Yes |
| Change deal stage | `change_crm_deal_stage` RPC + activity insert | Yes | Yes, via RPC | Deal stage RPC | Complete for stage path |
| Mark deal lost | `mark_crm_deal_lost` RPC + lost protection | Yes | Yes, via RPC | Lost-deal RPC | Complete for lost path |
| Presentation approval | PostgreSQL approval functions/triggers | Yes | Yes, via RPC | Approval service | Contract façade needed |
| Design-task approval | PostgreSQL functions/triggers | Yes | Yes, via RPC | Approval service | Contract façade needed |
| Deal → Project | `create_project_from_won_deal_v2` RPC | Yes | Yes, via RPC | Project conversion RPC | Contract façade needed |
| Project update | `create_project_update_secure` + project access policy | Yes for authored updates | Yes, via RPC | Project update service | Complete for update path |
| Project assignment | `assign_project_team` + project access policy | Yes for team transition | Yes, via RPC | Team assignment service | Complete for assignment path |
| Project status | `change_project_status` + project access policy | Yes | Yes, via RPC | Project status service | Complete for status path |
| Project todo create/complete | `add_project_todo`/completion RPCs | Yes | Yes, via RPC | Project todo service | Contract façade needed |
| Client CRUD | Web client + CRM RLS | Partial | No | Client service/API | Yes |
| Employee directory | Narrow RPCs plus web queries | Partial | No | Directory API/RPC | Yes |
| File visibility/archive | Storage + archive/share RPCs | Yes in protected paths | Yes, via signed service | File service | Contract façade needed |
| Activity/history | DB triggers plus some web inserts | Partial | No | Server-side activity events | Yes |
| Notifications | DB triggers + email/push Edge Functions | Yes for generation | Yes, via service | Notification service | Contract façade needed |
| Business-card OCR | Browser Tesseract.js | No | No | Controlled service/client-assisted OCR | Yes |

## Dangerous frontend-only or mixed rules

The following remain mixed and must not be trusted in a native client:

- General task creation/update/delete and assignment decisions
- Client CRUD and relationship edits
- Project updates and some assignment mutations
- Some deal-field edits and order attachment sequencing
- Frontend validation and role-gated controls
- Browser-side OCR and parsed client data
- Some activity logging performed after a successful client mutation

The new high-risk mutation paths now use server-side RPCs:

- `change_crm_deal_stage`
- `mark_crm_deal_lost`
- `change_task_status`
- `assign_task`
- `change_project_status`
- `assign_project_team`
- `create_project_update_secure`
- `start_deal_approval`
- `finalize_crm_deal_approval`

## Supabase RLS coverage

Existing RLS and authorization functions remain in place for tasks, task lists,
comments, attachments, CRM deals, approvals, projects, project todos, clients,
profiles, permissions, notifications, and storage objects. The new functions
are restricted to `authenticated`; anonymous execution is revoked.

The Phase 2 migration also adds a shared attachment-metadata trigger (25 MB
maximum, allow-listed document/image MIME types, executable-name rejection and
bucket-scoped `storage://...` references). It does not make any private bucket
public and still requires short-lived signed URLs for downloads.

RLS must continue to be tested directly. Hidden UI controls are never considered
authorization.

## Shared service inventory

Reusable TypeScript contracts and service boundaries are in:

- `src/shared/domain-types.ts`
- `src/shared/domain-services.ts`
- `src/shared/domain-dto.ts`
- `src/shared/file-contracts.ts`
- `src/shared/auth-contract.ts`
- `src/shared/notification-contract.ts`
- `src/shared/index.ts`

The current web adapter is exposed by:

- `js/shared-services.js`

The bridge delegates to `db.js`, while the database remains authoritative. The
future native adapter can implement the same service names over a versioned API
without duplicating business rules.

## API contract for future mobile

The following is the intended contract. It is a service contract, not a claim
that REST routes already exist.

### Tasks

| Operation | Input | Output | Authorization | Validation/errors |
|---|---|---|---|---|
| List tasks | filters, cursor | sanitized task list | `can_view_task` | Invalid cursor/filter |
| Create task | task fields, assignees, visibility | task | creator/list permission | Required title/list/assignee rules |
| Update task | task id + allowed fields | task | `can_manage_task` | Ownership/visibility/date rules |
| Change status | task id, status | status transition | `change_task_status` | Unauthorized, unknown task, invalid status |
| Add comment | task id, content, attachments | comment | task visibility | Content/file limits |
| Upload attachment | task id, metadata, file | attachment + signed reference | task attachment policy | MIME/size/path validation |

### Deals

| Operation | Input | Output | Authorization | Validation/errors |
|---|---|---|---|---|
| List deals | filters, cursor | redacted deal list | CRM access | Financial fields redacted when required |
| Create/update deal | deal fields | deal | CRM RLS | Required contact fields |
| Change stage | deal id, target stage | transition event | `change_crm_deal_stage` | Workflow/approval/lost guards |
| Mark lost | deal id, reason | loss event | `mark_crm_deal_lost` | Reason required; lost deals protected |
| Start approval | deal id, request type/files | approval steps | approval-start permission | Quote/proposal requirements |
| Decide approval | step id, decision, note | step/workflow state | assigned approver/admin | Rejection reason required |
| Convert to project | deal id, order payload | project id | approved deal/team | Atomic duplicate-safe conversion |

### Projects

| Operation | Input | Output | Authorization | Validation/errors |
|---|---|---|---|---|
| List/detail | filters/project id | redacted project DTO | `can_access_project` | Financial redaction |
| Create from Won deal | deal id, order payload | project id | approved deal/team | Dates, active assignees, client snapshot |
| Assign team | project id, employee ids | assignment result | project manager/admin | Active employee validation |
| Add/complete todo | project id, title, assignees, due time | todo | manager/assignee rules | Required title/assignee/due time |
| Share attachment | attachment id, visible flag | visibility result | project attachment policy | Current attachment only |

### Clients, team, notifications

- Client list/create/update/delete: authenticated CRM service, enforced by CRM RLS.
- Employee directory: narrow, active-profile DTOs only; privileged profile data is
  never returned to an ordinary mobile client.
- Notifications: user-scoped list/read operations and server-generated deep links.
- File operations: private bucket references and short-lived signed URLs only.

## Deal → Project behavior

The authoritative path is `create_project_from_won_deal_v2`:

1. Locks and verifies the deal.
2. Requires an approved workflow.
3. Authorizes the deal team or management.
4. Validates event dates, start time, installation type, and active assignees.
5. Copies client information into a project snapshot.
6. Applies schedule defaults where omitted.
7. Creates or updates the project without duplicating it.
8. Marks the deal Won and records activity.

The native client must call this operation and must not reimplement it locally.

## Web migration report

The web application now routes these mutations through the shared server path:

- CRM stage drag/drop → `change_crm_deal_stage`
- Lost-deal submission → `mark_crm_deal_lost`
- Task status-only changes → `change_task_status`
- Task assignment → `assign_task`
- Project status → `change_project_status`
- Project team assignment → `assign_project_team`
- Project updates → `create_project_update_secure`
- Deal approval start → `start_deal_approval`
- Approved-deal Discussion finalization → `finalize_crm_deal_approval`

The remainder of the web application is intentionally unchanged and remains a
follow-up refactor area. The legacy Capacitor Android project is preserved.

## Mobile readiness

| Module | Status | Reason |
|---|---|---|
| Tasks | NOT READY (deployment pending) | Task façade RPCs, RLS policies, comments, attachments, and activity history are implemented in `20260917110000_task_backend_services.sql`; live Supabase authorization tests and migration deployment are still pending |
| Deals | NOT READY | Core transitions are protected, but a complete versioned API façade is missing |
| Projects | NOT READY | Accessible list, status, team assignment, todos and authored updates have secure paths; general edit/delete and file APIs remain direct |
| Clients | NOT READY | Direct table CRUD and browser-only OCR remain |
| Files | NOT READY | Private storage exists, but upload/download/share APIs and MIME limits need consolidation |
| Auth | NOT READY | Supabase Auth is reusable, but native secure token storage/API session contract is not implemented |
| Notifications | NOT READY | Backend delivery exists and shared device/deep-link contracts are defined; native registration endpoint and live RLS tests remain |

## Verification

- JavaScript syntax checks passed.
- Shared TypeScript syntax transformation passed.
- Security hardening regression test passed.
- CRM lifecycle, lost-deal, and task-completion tests passed.

Production migration application still requires Supabase authentication/linking
and has not been performed by this phase.

## Edge Functions

No Edge Function was changed in this phase. Existing email, push and document
expiry functions already validate bearer sessions or dispatcher secrets
internally; \`verify_jwt = false\` is retained for cron/service invocation, so
those endpoints still require their own runtime authorization checks.
