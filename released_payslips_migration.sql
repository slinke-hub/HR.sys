CREATE TABLE IF NOT EXISTS released_payslips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    employee_name VARCHAR(255) NOT NULL,
    month_year VARCHAR(7) NOT NULL, -- e.g., '2026-08'
    base_salary NUMERIC DEFAULT 0,
    commission NUMERIC DEFAULT 0,
    overtime_pay NUMERIC DEFAULT 0,
    deductions NUMERIC DEFAULT 0,
    net_pay NUMERIC DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Enable RLS
ALTER TABLE released_payslips ENABLE ROW LEVEL SECURITY;

-- Allow read access for authenticated users (admins can read all, employees can read their own if needed)
CREATE POLICY "Users can view their own released payslips or admins can view all"
ON released_payslips
FOR SELECT
TO authenticated
USING (
    employee_id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = auth.uid() AND (profiles.role = 'ADMIN' OR profiles.job_title ILIKE '%manager%')
    )
);

-- Allow admins to insert
CREATE POLICY "Admins can insert released payslips"
ON released_payslips
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = auth.uid() AND (profiles.role = 'ADMIN' OR profiles.job_title ILIKE '%manager%')
    )
);
