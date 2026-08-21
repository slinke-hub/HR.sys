-- Bring older announcements tables in line with the current application.
BEGIN;

ALTER TABLE public.announcements
    ADD COLUMN IF NOT EXISTS admin_id UUID REFERENCES auth.users(id),
    ADD COLUMN IF NOT EXISTS icon VARCHAR(50) DEFAULT 'megaphone';

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS announcements_authenticated_select ON public.announcements;
CREATE POLICY announcements_authenticated_select ON public.announcements
FOR SELECT TO authenticated USING(TRUE);

DROP POLICY IF EXISTS announcements_admin_insert ON public.announcements;
CREATE POLICY announcements_admin_insert ON public.announcements
FOR INSERT TO authenticated WITH CHECK(
    admin_id=auth.uid() AND EXISTS(
        SELECT 1 FROM public.profiles WHERE id=auth.uid() AND upper(COALESCE(role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN')
    )
);

GRANT SELECT,INSERT ON public.announcements TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
