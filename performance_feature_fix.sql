-- ============================================================
-- Performance Feature Fix
-- This creates the foreign key from tasks.assignee_id to
-- public.profiles(id) so Supabase can resolve the join
-- used by the Performance Report generator.
-- ============================================================

-- Step 1: Add an explicit FK from tasks.assignee_id → profiles.id
-- (safe to run even if the column already exists)
ALTER TABLE public.tasks
    ADD CONSTRAINT fk_tasks_assignee_profile
    FOREIGN KEY (assignee_id)
    REFERENCES public.profiles(id)
    ON DELETE SET NULL
    NOT VALID; -- NOT VALID skips scanning existing rows, so it's fast

-- Step 2: Validate the constraint in the background (optional but good practice)
ALTER TABLE public.tasks
    VALIDATE CONSTRAINT fk_tasks_assignee_profile;

-- Step 3: Make sure Admins/Managers/Supervisors can read ALL tasks
-- (needed to generate the full performance report)
DROP POLICY IF EXISTS "Admins have full access to tasks" ON public.tasks;
CREATE POLICY "Admins have full access to tasks"
    ON public.tasks
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
              AND role IN ('ADMIN', 'MANAGER', 'SUPERVISOR')
        )
    );
