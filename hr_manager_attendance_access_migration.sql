-- Permit active HR Managers to view all employee attendance records.
ALTER TABLE public.time_punches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "HR Managers can view all punches" ON public.time_punches;
CREATE POLICY "HR Managers can view all punches"
ON public.time_punches
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.profiles viewer
        WHERE viewer.id = auth.uid()
          AND COALESCE(viewer.is_active, TRUE) = TRUE
          AND UPPER(TRIM(COALESCE(viewer.job_title, ''))) = 'HR MANAGER'
    )
);
