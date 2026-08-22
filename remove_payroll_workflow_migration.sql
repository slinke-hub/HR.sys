-- Removes the Payroll Workflow Beta schema only.
-- The legacy public.payroll payslip table is intentionally preserved.
BEGIN;

DROP FUNCTION IF EXISTS public.advance_payroll_run(UUID, TEXT);

DROP TABLE IF EXISTS public.loan_repayments;
DROP TABLE IF EXISTS public.payroll_entries;
DROP TABLE IF EXISTS public.payroll_runs;
DROP TABLE IF EXISTS public.payroll_adjustments;
DROP TABLE IF EXISTS public.employee_loans;

DROP FUNCTION IF EXISTS public.is_payroll_manager(UUID);

NOTIFY pgrst, 'reload schema';

COMMIT;
