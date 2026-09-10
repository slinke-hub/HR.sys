-- Professional project portfolio, deliberately independent from task records.
BEGIN;

ALTER TABLE public.projects
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS project_manager_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS lifecycle_status TEXT NOT NULL DEFAULT 'PLANNING',
    ADD COLUMN IF NOT EXISTS health_status TEXT NOT NULL DEFAULT 'ON_TRACK',
    ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'MEDIUM',
    ADD COLUMN IF NOT EXISTS progress_percent INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS budget_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS actual_cost NUMERIC(14,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS client_name TEXT,
    ADD COLUMN IF NOT EXISTS milestones JSONB NOT NULL DEFAULT '[]'::JSONB,
    ADD COLUMN IF NOT EXISTS risks JSONB NOT NULL DEFAULT '[]'::JSONB,
    ADD COLUMN IF NOT EXISTS last_update TEXT,
    ADD COLUMN IF NOT EXISTS last_update_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE public.projects
SET lifecycle_status = CASE UPPER(REPLACE(COALESCE(project_status, ''), ' ', '_'))
    WHEN 'IN_PROGRESS' THEN 'ACTIVE'
    WHEN 'CONFIRMED' THEN 'ACTIVE'
    WHEN 'COMPLETED' THEN 'COMPLETED'
    WHEN 'ON_HOLD' THEN 'ON_HOLD'
    WHEN 'CANCELLED' THEN 'CANCELLED'
    ELSE lifecycle_status
END,
budget_amount = CASE WHEN budget_amount = 0 THEN COALESCE(project_amount, 0) ELSE budget_amount END,
actual_cost = CASE WHEN actual_cost = 0 THEN COALESCE(paid_amount, 0) ELSE actual_cost END,
client_name = COALESCE(client_name, (SELECT COALESCE(c.company, c.name) FROM public.crm_clients c WHERE c.id = projects.client_id)),
project_manager_id = COALESCE(project_manager_id, assigned_people[1]);

ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_lifecycle_status_check;
ALTER TABLE public.projects ADD CONSTRAINT projects_lifecycle_status_check
    CHECK (lifecycle_status IN ('PLANNING', 'ACTIVE', 'ON_HOLD', 'COMPLETED', 'CANCELLED'));
ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_health_status_check;
ALTER TABLE public.projects ADD CONSTRAINT projects_health_status_check
    CHECK (health_status IN ('ON_TRACK', 'AT_RISK', 'OFF_TRACK'));
ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_priority_check;
ALTER TABLE public.projects ADD CONSTRAINT projects_priority_check
    CHECK (priority IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'));
ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_progress_percent_check;
ALTER TABLE public.projects ADD CONSTRAINT projects_progress_percent_check
    CHECK (progress_percent BETWEEN 0 AND 100);
ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_milestones_array_check;
ALTER TABLE public.projects ADD CONSTRAINT projects_milestones_array_check
    CHECK (jsonb_typeof(milestones) = 'array');
ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_risks_array_check;
ALTER TABLE public.projects ADD CONSTRAINT projects_risks_array_check
    CHECK (jsonb_typeof(risks) = 'array');

CREATE INDEX IF NOT EXISTS projects_lifecycle_status_idx ON public.projects(lifecycle_status);
CREATE INDEX IF NOT EXISTS projects_health_status_idx ON public.projects(health_status);
CREATE INDEX IF NOT EXISTS projects_manager_idx ON public.projects(project_manager_id);

CREATE OR REPLACE FUNCTION public.is_project_portfolio_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(COALESCE(profile.role, ''))) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'MANAGER', 'SUPERVISOR')
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) IN
                 ('GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER')
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_access_project(p_project_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.projects project
        WHERE project.id = p_project_id
          AND (
              project.created_by = p_user_id
              OR project.project_manager_id = p_user_id
              OR p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
              OR public.is_project_portfolio_admin(p_user_id)
          )
    );
$$;

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view projects they are assigned to or if they are admin" ON public.projects;
DROP POLICY IF EXISTS "Admins can insert projects" ON public.projects;
DROP POLICY IF EXISTS "Admins can update projects" ON public.projects;
DROP POLICY IF EXISTS project_portfolio_select ON public.projects;
DROP POLICY IF EXISTS project_portfolio_insert ON public.projects;
DROP POLICY IF EXISTS project_portfolio_update ON public.projects;
DROP POLICY IF EXISTS project_portfolio_delete ON public.projects;
CREATE POLICY project_portfolio_select ON public.projects FOR SELECT TO authenticated USING (
    created_by = auth.uid() OR project_manager_id = auth.uid()
    OR auth.uid() = ANY(COALESCE(assigned_people, ARRAY[]::UUID[]))
    OR public.is_project_portfolio_admin(auth.uid())
);
CREATE POLICY project_portfolio_insert ON public.projects FOR INSERT TO authenticated WITH CHECK (
    created_by = auth.uid() AND (project_manager_id = auth.uid() OR public.is_project_portfolio_admin(auth.uid()))
);
CREATE POLICY project_portfolio_update ON public.projects FOR UPDATE TO authenticated USING (
    created_by = auth.uid() OR project_manager_id = auth.uid() OR public.is_project_portfolio_admin(auth.uid())
) WITH CHECK (
    created_by = auth.uid() OR project_manager_id = auth.uid() OR public.is_project_portfolio_admin(auth.uid())
);
CREATE POLICY project_portfolio_delete ON public.projects FOR DELETE TO authenticated USING (
    created_by = auth.uid() OR project_manager_id = auth.uid() OR public.is_project_portfolio_admin(auth.uid())
);

CREATE TABLE IF NOT EXISTS public.project_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    update_type TEXT NOT NULL DEFAULT 'UPDATE' CHECK (update_type IN ('UPDATE', 'DECISION', 'MILESTONE', 'RISK')),
    summary TEXT NOT NULL CHECK (CHAR_LENGTH(BTRIM(summary)) BETWEEN 1 AND 4000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS project_updates_project_created_idx ON public.project_updates(project_id, created_at DESC);
ALTER TABLE public.project_updates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS project_updates_select ON public.project_updates;
DROP POLICY IF EXISTS project_updates_insert ON public.project_updates;
CREATE POLICY project_updates_select ON public.project_updates FOR SELECT TO authenticated
USING (public.can_access_project(project_id, auth.uid()));
CREATE POLICY project_updates_insert ON public.project_updates FOR INSERT TO authenticated
WITH CHECK (author_id = auth.uid() AND public.can_access_project(project_id, auth.uid()));

CREATE OR REPLACE FUNCTION public.touch_project_from_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    UPDATE public.projects
    SET last_update = NEW.summary, last_update_at = NEW.created_at, updated_at = NOW()
    WHERE id = NEW.project_id;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS project_updates_touch_project ON public.project_updates;
CREATE TRIGGER project_updates_touch_project
AFTER INSERT ON public.project_updates FOR EACH ROW EXECUTE FUNCTION public.touch_project_from_update();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.projects TO authenticated;
GRANT SELECT, INSERT ON public.project_updates TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_project_portfolio_admin(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_project(UUID, UUID) TO authenticated;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.projects;
EXCEPTION WHEN duplicate_object OR undefined_object THEN NULL;
END $$;
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.project_updates;
EXCEPTION WHEN duplicate_object OR undefined_object THEN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
