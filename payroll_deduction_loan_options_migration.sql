-- Require deduction descriptions and support full or installment loan payments.
BEGIN;
ALTER TABLE public.payroll_entries
  ADD COLUMN IF NOT EXISTS deduction_description TEXT,
  ADD COLUMN IF NOT EXISTS loan_payment_mode TEXT NOT NULL DEFAULT 'INSTALLMENT';

ALTER TABLE public.payroll_entries DROP CONSTRAINT IF EXISTS payroll_entries_loan_payment_mode_check;
ALTER TABLE public.payroll_entries ADD CONSTRAINT payroll_entries_loan_payment_mode_check
  CHECK(loan_payment_mode IN('INSTALLMENT','FULL'));

ALTER TABLE public.payroll_entries DROP CONSTRAINT IF EXISTS payroll_entries_deduction_description_check;
ALTER TABLE public.payroll_entries ADD CONSTRAINT payroll_entries_deduction_description_check
  CHECK(deductions=0 OR NULLIF(BTRIM(deduction_description),'') IS NOT NULL);

ALTER TABLE public.payroll_entries DROP CONSTRAINT IF EXISTS payroll_entries_loan_reference_check;
ALTER TABLE public.payroll_entries ADD CONSTRAINT payroll_entries_loan_reference_check
  CHECK(loan_installment=0 OR loan_id IS NOT NULL);

COMMENT ON COLUMN public.payroll_entries.deduction_description IS 'Required explanation when deductions are greater than zero.';
COMMENT ON COLUMN public.payroll_entries.loan_payment_mode IS 'INSTALLMENT deducts the scheduled amount; FULL attempts the remaining balance without allowing negative net pay.';
NOTIFY pgrst,'reload schema';
COMMIT;
