-- 1. Drop the unique constraint on employee_id if it exists, to allow for multiple/historical contracts
ALTER TABLE public.contracts
    DROP CONSTRAINT IF EXISTS contracts_employee_id_key;

-- 2. Ensure the confidentiality_policy_url column exists
ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS confidentiality_policy_url TEXT;

-- 3. Ensure the is_archived column exists (useful if you ever want to soft-delete contracts)
ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_by UUID;

-- 4. Add Job Title in Arabic if it's missing
ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS job_title_ar VARCHAR(255),
    ADD COLUMN IF NOT EXISTS job_title_en VARCHAR(255),
    ADD COLUMN IF NOT EXISTS department VARCHAR(255),
    ADD COLUMN IF NOT EXISTS nationality VARCHAR(100);

-- 5. Deduplicate and clean up any bad data (Optional but recommended)
-- This ensures if there are multiple active contracts for one employee, we only keep the newest one active
-- and mark the older ones as 'Expired' (and archive them).
UPDATE public.contracts
SET is_archived = TRUE, status = 'Expired'
WHERE id IN (
    SELECT id
    FROM (
        SELECT id,
               ROW_NUMBER() OVER(PARTITION BY employee_id ORDER BY created_at DESC) as rnum
        FROM public.contracts
        WHERE employee_id IS NOT NULL AND (is_archived = FALSE OR is_archived IS NULL)
    ) t
    WHERE t.rnum > 1
);

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
