-- Create payroll table
CREATE TABLE IF NOT EXISTS public.payroll (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    month_year TEXT NOT NULL,
    net_pay NUMERIC(10, 2) NOT NULL DEFAULT 0,
    overtime_pay NUMERIC(10, 2) NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.payroll ENABLE ROW LEVEL SECURITY;

-- Payroll policies
DROP POLICY IF EXISTS "Users can view own payroll" ON public.payroll;
CREATE POLICY "Users can view own payroll"
    ON public.payroll FOR SELECT
    USING (auth.uid() = employee_id);

DROP POLICY IF EXISTS "Admins can view all payroll" ON public.payroll;
CREATE POLICY "Admins can view all payroll"
    ON public.payroll FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'
        )
    );

DROP POLICY IF EXISTS "Admins can insert payroll" ON public.payroll;
CREATE POLICY "Admins can insert payroll"
    ON public.payroll FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'
        )
    );

DROP POLICY IF EXISTS "Admins can update payroll" ON public.payroll;
CREATE POLICY "Admins can update payroll"
    ON public.payroll FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'
        )
    );

DROP POLICY IF EXISTS "Admins can delete payroll" ON public.payroll;
CREATE POLICY "Admins can delete payroll"
    ON public.payroll FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid() AND profiles.role = 'Admin'
        )
    );
