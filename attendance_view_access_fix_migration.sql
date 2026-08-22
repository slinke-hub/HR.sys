-- The active clock-in/out workflow writes to public.attendance. Ensure Admins
-- and active HR Managers can read every employee record from that table.
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "HR Managers can view all attendance" ON public.attendance;
CREATE POLICY "HR Managers can view all attendance"
ON public.attendance FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles viewer
        WHERE viewer.id = auth.uid()
          AND COALESCE(viewer.is_active, TRUE) = TRUE
          AND UPPER(TRIM(COALESCE(viewer.job_title, ''))) = 'HR MANAGER'
    )
);

DROP POLICY IF EXISTS "System Admins can view all attendance" ON public.attendance;
CREATE POLICY "System Admins can view all attendance"
ON public.attendance FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles viewer
        WHERE viewer.id = auth.uid()
          AND UPPER(TRIM(COALESCE(viewer.role, ''))) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
    )
);

NOTIFY pgrst, 'reload schema';
