-- Allow active HR Managers to create and edit employee contracts.
-- The existing administrator policy remains in place.
ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "HR Managers can manage contracts" ON public.contracts;
CREATE POLICY "HR Managers can manage contracts"
ON public.contracts
FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = auth.uid()
          AND is_active IS DISTINCT FROM FALSE
          AND UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = auth.uid()
          AND is_active IS DISTINCT FROM FALSE
          AND UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
    )
);
