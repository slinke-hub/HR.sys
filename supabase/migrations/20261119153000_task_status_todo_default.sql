BEGIN;

-- Keep new tasks in the same initial state even when a caller omits status.
-- Existing task rows and later workflow transitions are unchanged.
ALTER TABLE public.tasks
    ALTER COLUMN status SET DEFAULT 'todo';

CREATE OR REPLACE FUNCTION public.apply_task_creation_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    department_manager_id uuid;
BEGIN
    IF NEW.status IS NULL OR NULLIF(BTRIM(NEW.status), '') IS NULL THEN
        NEW.status := 'todo';
    END IF;

    IF NEW.assignee_id IS NULL THEN
        NEW.assignee_id := NEW.created_by;
    END IF;

    IF NEW.supervisor_id IS NULL AND NULLIF(BTRIM(NEW.department), '') IS NOT NULL THEN
        SELECT COALESCE(
            department.head_id,
            NULLIF(to_jsonb(department)->>'manager_id', '')::uuid
        )
        INTO department_manager_id
        FROM public.departments AS department
        WHERE department.id::text = NEW.department
           OR department.name = NEW.department
           OR COALESCE(to_jsonb(department)->>'name_ar', '') = NEW.department
        ORDER BY CASE WHEN department.name = NEW.department THEN 0 ELSE 1 END
        LIMIT 1;

        NEW.supervisor_id := department_manager_id;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.apply_task_creation_defaults() IS
    'Defaults new tasks to todo, defaults an unassigned task to its creator, and resolves an unset supervisor from the selected department manager.';

NOTIFY pgrst, 'reload schema';

COMMIT;
