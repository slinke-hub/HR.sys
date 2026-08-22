-- PAYROLL WORKFLOW BETA — PREPARED FOR REVIEW, NOT YET DEPLOYED.
-- Workflow: Draft -> Review -> Approved -> Paid.
BEGIN;

CREATE TABLE IF NOT EXISTS public.employee_loans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  approved_request_id UUID REFERENCES public.requests(id) ON DELETE SET NULL,
  original_amount NUMERIC(12,2) NOT NULL CHECK(original_amount>0),
  remaining_balance NUMERIC(12,2) NOT NULL CHECK(remaining_balance>=0),
  monthly_installment NUMERIC(12,2) NOT NULL CHECK(monthly_installment>0),
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN('ACTIVE','PAID','SUSPENDED')),
  start_month DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.payroll_adjustments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  adjustment_type TEXT NOT NULL CHECK(adjustment_type IN('SALARY_RAISE','CASH_REWARD','COMMISSION','DEDUCTION')),
  amount NUMERIC(12,2) NOT NULL CHECK(amount>0),
  effective_month DATE NOT NULL,
  is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'APPROVED' CHECK(status IN('DRAFT','APPROVED','CANCELLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.payroll_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_month DATE NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','REVIEW','APPROVED','PAID','CANCELLED')),
  created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reviewed_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  approved_by UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.payroll_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_run_id UUID NOT NULL REFERENCES public.payroll_runs(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  payable_days NUMERIC(5,2) NOT NULL CHECK(payable_days>=0),
  days_in_month INTEGER NOT NULL CHECK(days_in_month BETWEEN 28 AND 31),
  basic_salary NUMERIC(12,2) NOT NULL CHECK(basic_salary>=0),
  salary_raise NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(salary_raise>=0),
  earned_basic_salary NUMERIC(12,2) NOT NULL CHECK(earned_basic_salary>=0),
  deductions NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(deductions>=0),
  deduction_description TEXT,
  loan_id UUID REFERENCES public.employee_loans(id) ON DELETE RESTRICT,
  loan_payment_mode TEXT NOT NULL DEFAULT 'INSTALLMENT' CHECK(loan_payment_mode IN('INSTALLMENT','FULL')),
  loan_installment NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(loan_installment>=0),
  cash_reward NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(cash_reward>=0),
  commission NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(commission>=0),
  gross_pay NUMERIC(12,2) NOT NULL CHECK(gross_pay>=0),
  net_salary NUMERIC(12,2) NOT NULL CHECK(net_salary>=0),
  transfer_method TEXT NOT NULL DEFAULT 'Cash' CHECK(transfer_method IN('Cash','Bank Transfer')),
  iban TEXT,
  calculation_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(payroll_run_id,employee_id),
  CHECK(transfer_method='Cash' OR NULLIF(BTRIM(iban),'') IS NOT NULL),
  CHECK(deductions=0 OR NULLIF(BTRIM(deduction_description),'') IS NOT NULL),
  CHECK(loan_installment=0 OR loan_id IS NOT NULL)
);

-- Loan balances change only when a payroll run moves to PAID. Generating or
-- approving a payslip never deducts the balance twice.
CREATE TABLE IF NOT EXISTS public.loan_repayments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id UUID NOT NULL REFERENCES public.employee_loans(id) ON DELETE RESTRICT,
  payroll_entry_id UUID NOT NULL UNIQUE REFERENCES public.payroll_entries(id) ON DELETE RESTRICT,
  amount NUMERIC(12,2) NOT NULL CHECK(amount>0),
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.employee_loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loan_repayments ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_payroll_manager(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=p_user_id AND (
      upper(COALESCE(profile.role,'')) IN('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
      OR upper(BTRIM(COALESCE(profile.job_title,'')))='FINANCE MANAGER'
    )
  );
$$;

CREATE POLICY employee_loans_own_select ON public.employee_loans FOR SELECT TO authenticated
  USING(employee_id=auth.uid() OR public.is_payroll_manager(auth.uid()));
CREATE POLICY employee_loans_manager_all ON public.employee_loans FOR ALL TO authenticated
  USING(public.is_payroll_manager(auth.uid())) WITH CHECK(public.is_payroll_manager(auth.uid()));

CREATE POLICY payroll_adjustments_own_select ON public.payroll_adjustments FOR SELECT TO authenticated
  USING(employee_id=auth.uid() OR public.is_payroll_manager(auth.uid()));
CREATE POLICY payroll_adjustments_manager_all ON public.payroll_adjustments FOR ALL TO authenticated
  USING(public.is_payroll_manager(auth.uid())) WITH CHECK(public.is_payroll_manager(auth.uid()));

CREATE POLICY payroll_runs_manager_all ON public.payroll_runs FOR ALL TO authenticated
  USING(public.is_payroll_manager(auth.uid())) WITH CHECK(public.is_payroll_manager(auth.uid()));

CREATE POLICY payroll_entries_own_select ON public.payroll_entries FOR SELECT TO authenticated
  USING(employee_id=auth.uid() OR public.is_payroll_manager(auth.uid()));
CREATE POLICY payroll_entries_manager_all ON public.payroll_entries FOR ALL TO authenticated
  USING(public.is_payroll_manager(auth.uid())) WITH CHECK(public.is_payroll_manager(auth.uid()));

CREATE POLICY loan_repayments_own_select ON public.loan_repayments FOR SELECT TO authenticated USING(
  public.is_payroll_manager(auth.uid()) OR EXISTS(
    SELECT 1 FROM public.employee_loans loan WHERE loan.id=loan_id AND loan.employee_id=auth.uid()
  )
);
CREATE POLICY loan_repayments_manager_all ON public.loan_repayments FOR ALL TO authenticated
  USING(public.is_payroll_manager(auth.uid())) WITH CHECK(public.is_payroll_manager(auth.uid()));

CREATE OR REPLACE FUNCTION public.advance_payroll_run(p_run_id UUID,p_next_status TEXT)
RETURNS public.payroll_runs
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE run_row public.payroll_runs%ROWTYPE; normalized TEXT:=upper(BTRIM(p_next_status)); entry RECORD;
BEGIN
  IF NOT public.is_payroll_manager(auth.uid()) THEN RAISE EXCEPTION 'Payroll access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO run_row FROM public.payroll_runs WHERE id=p_run_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found'; END IF;
  IF NOT ((run_row.status='DRAFT' AND normalized='REVIEW') OR (run_row.status='REVIEW' AND normalized='APPROVED') OR (run_row.status='APPROVED' AND normalized='PAID') OR normalized='CANCELLED') THEN
    RAISE EXCEPTION 'Invalid payroll transition: % to %',run_row.status,normalized;
  END IF;
  IF normalized='PAID' THEN
    FOR entry IN SELECT payroll_entry.id,loan.id loan_id,payroll_entry.loan_installment
      FROM public.payroll_entries payroll_entry
      JOIN public.employee_loans loan ON loan.id=payroll_entry.loan_id AND loan.employee_id=payroll_entry.employee_id AND loan.status='ACTIVE'
      WHERE payroll_entry.payroll_run_id=p_run_id AND payroll_entry.loan_installment>0
    LOOP
      INSERT INTO public.loan_repayments(loan_id,payroll_entry_id,amount)
      VALUES(entry.loan_id,entry.id,entry.loan_installment)
      ON CONFLICT(payroll_entry_id) DO NOTHING;
      IF FOUND THEN
        UPDATE public.employee_loans SET remaining_balance=GREATEST(0,remaining_balance-entry.loan_installment),
          status=CASE WHEN remaining_balance-entry.loan_installment<=0 THEN 'PAID' ELSE status END
        WHERE id=entry.loan_id;
      END IF;
    END LOOP;
  END IF;
  UPDATE public.payroll_runs SET status=normalized,reviewed_by=CASE WHEN normalized='REVIEW' THEN auth.uid() ELSE reviewed_by END,
    approved_by=CASE WHEN normalized='APPROVED' THEN auth.uid() ELSE approved_by END,
    paid_at=CASE WHEN normalized='PAID' THEN now() ELSE paid_at END,updated_at=now()
  WHERE id=p_run_id RETURNING * INTO run_row;
  RETURN run_row;
END;
$$;

REVOKE ALL ON FUNCTION public.advance_payroll_run(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.advance_payroll_run(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_payroll_manager(UUID) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
