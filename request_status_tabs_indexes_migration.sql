-- Supports the Pending, Approved, and Rejected request tabs without changing
-- request data or approval behavior.

create index if not exists idx_request_approval_workflows_status_created_at
    on public.request_approval_workflows (status, created_at desc);

create index if not exists idx_requests_status_created_at
    on public.requests (status, created_at desc);

create index if not exists idx_leave_requests_status_created_at
    on public.leave_requests (status, created_at desc);

create index if not exists idx_document_requests_status_created_at
    on public.document_requests (status, created_at desc);

create index if not exists idx_expenses_status_created_at
    on public.expenses (status, created_at desc);

create index if not exists idx_time_punches_employee_time
    on public.time_punches (employee_id, punch_time desc);
