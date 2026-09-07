BEGIN;

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS source_link TEXT;

CREATE OR REPLACE FUNCTION public.apply_task_creation_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    department_manager_id uuid;
BEGIN
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

DROP TRIGGER IF EXISTS tasks_apply_creation_defaults ON public.tasks;
CREATE TRIGGER tasks_apply_creation_defaults
BEFORE INSERT ON public.tasks
FOR EACH ROW
EXECUTE FUNCTION public.apply_task_creation_defaults();

COMMENT ON FUNCTION public.apply_task_creation_defaults() IS
    'Defaults an unassigned task to its creator and resolves an unset supervisor from the selected department manager.';
COMMENT ON COLUMN public.tasks.source_link IS
    'Optional shared URL for regular tasks, or the primary source URL for design tasks.';

NOTIFY pgrst, 'reload schema';

COMMIT;
