-- Create contracts table
CREATE TABLE IF NOT EXISTS public.contracts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id) UNIQUE,
    contract_type VARCHAR(50) DEFAULT 'Full-time',
    start_date DATE NOT NULL,
    end_date DATE,
    salary DECIMAL(10, 2),
    status VARCHAR(20) DEFAULT 'Active' CHECK (status IN ('Active', 'Terminated', 'Expired')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

-- Policies
-- Admins can do everything
CREATE POLICY "Admins have full access to contracts" ON public.contracts
    FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

CREATE POLICY "HR Managers can manage contracts" ON public.contracts
    FOR ALL
    USING (EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND is_active IS DISTINCT FROM FALSE
          AND UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND is_active IS DISTINCT FROM FALSE
          AND UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
    ));

-- Employees can view their own contracts
CREATE POLICY "Employees can view their own contracts" ON public.contracts
    FOR SELECT USING (auth.uid() = employee_id);

-- Optional: Create a trigger to auto-update the updated_at column
CREATE OR REPLACE FUNCTION update_modified_column() 
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW; 
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_contracts_modtime ON public.contracts;
CREATE TRIGGER update_contracts_modtime
    BEFORE UPDATE ON public.contracts
    FOR EACH ROW EXECUTE PROCEDURE update_modified_column();
