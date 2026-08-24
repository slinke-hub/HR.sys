-- 1. Payroll Settings
CREATE TABLE IF NOT EXISTS public.payroll_settings (
    id INTEGER PRIMARY KEY DEFAULT 1,
    is_overtime_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ensure only one row exists
INSERT INTO public.payroll_settings (id, is_overtime_enabled) 
VALUES (1, TRUE) 
ON CONFLICT (id) DO NOTHING;

-- 2. Commission Tiers
CREATE TABLE IF NOT EXISTS public.commission_tiers (
    id SERIAL PRIMARY KEY,
    min_target_percentage DECIMAL(5, 2) NOT NULL, -- e.g., 51.00 for 51%
    max_target_percentage DECIMAL(5, 2), -- e.g., 100.00, NULL means infinity
    commission_percentage DECIMAL(5, 2) NOT NULL, -- e.g., 5.00 for 5%
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Default Tiers based on scenario
INSERT INTO public.commission_tiers (min_target_percentage, max_target_percentage, commission_percentage)
VALUES 
(0.00, 50.00, 0.00),
(51.00, 100.00, 5.00),
(101.00, NULL, 10.00);

-- 3. Monthly Sales
CREATE TABLE IF NOT EXISTS public.monthly_sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    month_year VARCHAR(7) NOT NULL, -- Format: YYYY-MM
    actual_sales_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(employee_id, month_year)
);

-- 4. Absences
CREATE TABLE IF NOT EXISTS public.absences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    date_of_absence DATE NOT NULL,
    is_excused BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(employee_id, date_of_absence)
);

-- 5. Employee Loans
CREATE TABLE IF NOT EXISTS public.employee_loans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    requested_amount DECIMAL(10, 2) NOT NULL,
    monthly_installment DECIMAL(10, 2) NOT NULL,
    remaining_balance DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'PAID')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. Payroll Adjustments
CREATE TABLE IF NOT EXISTS public.payroll_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    month_year VARCHAR(7) NOT NULL, -- Format: YYYY-MM
    amount DECIMAL(10, 2) NOT NULL, -- Positive for rewards, negative for penalties
    reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. Update Profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS hire_date DATE,
ADD COLUMN IF NOT EXISTS monthly_sales_target DECIMAL(10, 2) DEFAULT 0.00;

-- 8. Update Payroll
ALTER TABLE public.payroll
ADD COLUMN IF NOT EXISTS base_salary DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS commission_amount DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS loan_deduction DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS absence_deduction DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS adjustments_total DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS is_final_settlement BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS eos_amount DECIMAL(10, 2) DEFAULT 0.00;

-- RLS Policies (Admins and HR Managers can access everything, Employees can view their own)
ALTER TABLE public.payroll_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commission_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.absences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_adjustments ENABLE ROW LEVEL SECURITY;

-- Simple permissive policies for beta (can be tightened later)
DROP POLICY IF EXISTS "Allow all access to payroll_settings for authenticated users" ON public.payroll_settings;
CREATE POLICY "Allow all access to payroll_settings for authenticated users" ON public.payroll_settings FOR ALL USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Allow all access to commission_tiers for authenticated users" ON public.commission_tiers;
CREATE POLICY "Allow all access to commission_tiers for authenticated users" ON public.commission_tiers FOR ALL USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Allow all access to monthly_sales for authenticated users" ON public.monthly_sales;
CREATE POLICY "Allow all access to monthly_sales for authenticated users" ON public.monthly_sales FOR ALL USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Allow all access to absences for authenticated users" ON public.absences;
CREATE POLICY "Allow all access to absences for authenticated users" ON public.absences FOR ALL USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Allow all access to employee_loans for authenticated users" ON public.employee_loans;
CREATE POLICY "Allow all access to employee_loans for authenticated users" ON public.employee_loans FOR ALL USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "Allow all access to payroll_adjustments for authenticated users" ON public.payroll_adjustments;
CREATE POLICY "Allow all access to payroll_adjustments for authenticated users" ON public.payroll_adjustments FOR ALL USING (auth.role() = 'authenticated');


-- ============================================================================
-- FIX: If you already ran this script previously and got a 400 Bad Request error, 
-- running this section will update the foreign keys to point to public.profiles
-- so that PostgREST joins work correctly.
-- ============================================================================

ALTER TABLE IF EXISTS public.monthly_sales 
DROP CONSTRAINT IF EXISTS monthly_sales_employee_id_fkey;
ALTER TABLE IF EXISTS public.monthly_sales 
ADD CONSTRAINT monthly_sales_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE IF EXISTS public.absences 
DROP CONSTRAINT IF EXISTS absences_employee_id_fkey;
ALTER TABLE IF EXISTS public.absences 
ADD CONSTRAINT absences_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE IF EXISTS public.employee_loans 
DROP CONSTRAINT IF EXISTS employee_loans_employee_id_fkey;
ALTER TABLE IF EXISTS public.employee_loans 
ADD CONSTRAINT employee_loans_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE IF EXISTS public.payroll_adjustments 
DROP CONSTRAINT IF EXISTS payroll_adjustments_employee_id_fkey;
ALTER TABLE IF EXISTS public.payroll_adjustments 
ADD CONSTRAINT payroll_adjustments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

NOTIFY pgrst, 'reload schema';
