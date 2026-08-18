-- Adds a department-manager supervisor to new tasks.
-- Safe to run more than once in the Supabase SQL Editor.

BEGIN;

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS supervisor_id UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'tasks_supervisor_id_fkey'
          AND conrelid = 'public.tasks'::regclass
    ) THEN
        ALTER TABLE public.tasks
            ADD CONSTRAINT tasks_supervisor_id_fkey
            FOREIGN KEY (supervisor_id)
            REFERENCES public.profiles(id)
            ON DELETE SET NULL;
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS tasks_supervisor_id_idx
    ON public.tasks(supervisor_id);

CREATE OR REPLACE FUNCTION public.get_my_department_supervisors()
RETURNS TABLE (id UUID, full_name TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT
        department_head.id,
        COALESCE(NULLIF(BTRIM(department_head.full_name), ''), 'Department Manager')::TEXT
    FROM public.profiles AS employee
    JOIN public.departments AS department
      ON department.id = employee.department_id
    JOIN public.profiles AS department_head
      ON department_head.id = department.head_id
    WHERE employee.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_department_supervisors() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_department_supervisors() TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_task_department_supervisor()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    expected_supervisor_id UUID;
    caller_role TEXT;
BEGIN
    IF TG_OP = 'UPDATE'
       AND (
           NEW.supervisor_id IS DISTINCT FROM OLD.supervisor_id
           OR NEW.created_by IS DISTINCT FROM OLD.created_by
       )
       AND auth.uid() IS NOT NULL THEN
        SELECT profile.role
        INTO caller_role
        FROM public.profiles AS profile
        WHERE profile.id = auth.uid();

        IF auth.uid() IS DISTINCT FROM OLD.created_by
           AND caller_role IS DISTINCT FROM 'ADMIN' THEN
            RAISE EXCEPTION 'Only the task creator or an administrator can change the task supervisor'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    SELECT department.head_id
    INTO expected_supervisor_id
    FROM public.profiles AS creator
    LEFT JOIN public.departments AS department
      ON department.id = creator.department_id
    WHERE creator.id = NEW.created_by;

    IF NEW.supervisor_id IS DISTINCT FROM expected_supervisor_id THEN
        IF expected_supervisor_id IS NULL THEN
            RAISE EXCEPTION 'No department manager is assigned to the task creator'
                USING ERRCODE = '23514';
        END IF;

        RAISE EXCEPTION 'Selected supervisor must be the task creator''s department manager'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_task_department_supervisor() FROM PUBLIC;

DROP TRIGGER IF EXISTS validate_task_department_supervisor_trigger ON public.tasks;
CREATE TRIGGER validate_task_department_supervisor_trigger
    BEFORE INSERT OR UPDATE OF supervisor_id, created_by
    ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_task_department_supervisor();

DROP POLICY IF EXISTS "Supervisors can view supervised tasks" ON public.tasks;
CREATE POLICY "Supervisors can view supervised tasks"
    ON public.tasks
    FOR SELECT
    USING (auth.uid() = supervisor_id);

DROP POLICY IF EXISTS "Supervisors can update supervised tasks" ON public.tasks;
CREATE POLICY "Supervisors can update supervised tasks"
    ON public.tasks
    FOR UPDATE
    USING (auth.uid() = supervisor_id)
    WITH CHECK (auth.uid() = supervisor_id);

NOTIFY pgrst, 'reload schema';

COMMIT;
