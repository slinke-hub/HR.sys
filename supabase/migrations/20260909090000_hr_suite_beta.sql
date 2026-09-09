-- Isolated beta workspace for testing end-to-end HR lifecycle workflows.
BEGIN;

CREATE TABLE IF NOT EXISTS public.hr_suite_beta_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL CHECK (category IN ('RECRUITMENT','ONBOARDING','LEAVE','PAYROLL','COMPLIANCE','OFFBOARDING')),
    title TEXT NOT NULL CHECK (BTRIM(title) <> ''),
    title_ar TEXT,
    employee_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    owner_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','OPEN','IN_PROGRESS','BLOCKED','READY','COMPLETED','ARCHIVED')),
    priority TEXT NOT NULL DEFAULT 'MEDIUM' CHECK (priority IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    due_date DATE,
    amount NUMERIC(14,2) CHECK (amount IS NULL OR amount >= 0),
    notes TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_by UUID DEFAULT auth.uid() REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS hr_suite_beta_items_category_status_idx ON public.hr_suite_beta_items(category,status);
CREATE INDEX IF NOT EXISTS hr_suite_beta_items_due_date_idx ON public.hr_suite_beta_items(due_date) WHERE status NOT IN ('COMPLETED','ARCHIVED');

CREATE OR REPLACE FUNCTION public.can_manage_hr_suite_beta(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role,''), '[_-]+', ' ', 'g'))) IN ('ADMIN','OWNER','ROLE SYSTEM ADMIN','SYSTEM ADMIN','HR MANAGER')
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.job_title,''), '[_-]+', ' ', 'g'))) IN ('HR MANAGER','FINANCE MANAGER','ACCOUNTANT MANAGER','GM','GENERAL MANAGER','CEO','CHIEF EXECUTIVE','CHIEF EXECUTIVE OFFICER')
              OR BTRIM(COALESCE(viewer.job_title_ar,'')) IN ('مدير الموارد البشرية','المدير المالي','مدير الحسابات','المدير العام','الرئيس التنفيذي')
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.set_hr_suite_beta_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_by := auth.uid();
    END IF;
    NEW.updated_by := auth.uid();
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS hr_suite_beta_items_audit ON public.hr_suite_beta_items;
CREATE TRIGGER hr_suite_beta_items_audit
BEFORE INSERT OR UPDATE ON public.hr_suite_beta_items
FOR EACH ROW EXECUTE FUNCTION public.set_hr_suite_beta_audit();

ALTER TABLE public.hr_suite_beta_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hr_suite_beta_select ON public.hr_suite_beta_items;
DROP POLICY IF EXISTS hr_suite_beta_insert ON public.hr_suite_beta_items;
DROP POLICY IF EXISTS hr_suite_beta_update ON public.hr_suite_beta_items;
CREATE POLICY hr_suite_beta_select ON public.hr_suite_beta_items FOR SELECT TO authenticated USING (public.can_manage_hr_suite_beta(auth.uid()));
CREATE POLICY hr_suite_beta_insert ON public.hr_suite_beta_items FOR INSERT TO authenticated WITH CHECK (public.can_manage_hr_suite_beta(auth.uid()));
CREATE POLICY hr_suite_beta_update ON public.hr_suite_beta_items FOR UPDATE TO authenticated USING (public.can_manage_hr_suite_beta(auth.uid())) WITH CHECK (public.can_manage_hr_suite_beta(auth.uid()));

REVOKE ALL ON FUNCTION public.can_manage_hr_suite_beta(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_hr_suite_beta(UUID) TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON public.hr_suite_beta_items TO authenticated;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='hr_suite_beta_items') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.hr_suite_beta_items;
    END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
