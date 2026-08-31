-- Clear requested HR transactional records while preserving all users and
-- account/profile data. Payroll settings and commission tiers are configuration
-- and are intentionally retained.
BEGIN;

TRUNCATE TABLE
    public.attendance,
    public.time_punches,
    public.leave_requests,
    public.document_requests,
    public.employee_documents,
    public.payroll,
    public.monthly_sales,
    public.absences,
    public.employee_loans,
    public.payroll_adjustments,
    public.released_payslips
RESTART IDENTITY CASCADE;

COMMIT;
