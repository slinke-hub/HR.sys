-- Require the fields used by the new-task workflow without rewriting historical rows.
-- Existing tasks remain readable even if they were created before these requirements.

CREATE OR REPLACE FUNCTION public.enforce_task_creation_required_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.assignee_id IS NULL THEN
        RAISE EXCEPTION 'Task assignee is required' USING ERRCODE = '22023';
    END IF;
    IF NEW.due_date IS NULL THEN
        RAISE EXCEPTION 'Task due date is required' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tasks_require_creation_fields ON public.tasks;
CREATE TRIGGER tasks_require_creation_fields
    BEFORE INSERT ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_task_creation_required_fields();
