-- Enable RLS on contracts
ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

-- Drop any conflicting restrictive policies if they exist
DROP POLICY IF EXISTS "Admin view all contracts" ON public.contracts;
DROP POLICY IF EXISTS "Contract managers can manage contracts" ON public.contracts;

-- Create a direct, simple policy for ADMINs to view all contracts
CREATE POLICY "Admin view all contracts"
ON public.contracts
FOR ALL 
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() 
    AND (UPPER(role) = 'ADMIN' OR UPPER(job_title) = 'HR MANAGER')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() 
    AND (UPPER(role) = 'ADMIN' OR UPPER(job_title) = 'HR MANAGER')
  )
);

-- Ensure employees can view their own contracts
DROP POLICY IF EXISTS "Employees can view own contract" ON public.contracts;
CREATE POLICY "Employees can view own contract"
ON public.contracts
FOR SELECT
TO authenticated
USING (employee_id = auth.uid());
