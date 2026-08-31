-- Admins may create tasks in any list without being constrained by the
-- creator-department supervisor validation. Other users retain the existing
-- supervisor rule.
BEGIN;

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
    SELECT profile.role INTO caller_role
    FROM public.profiles AS profile
    WHERE profile.id = auth.uid();

    IF UPPER(COALESCE(caller_role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN') THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE'
       AND (NEW.supervisor_id IS DISTINCT FROM OLD.supervisor_id OR NEW.created_by IS DISTINCT FROM OLD.created_by)
       AND auth.uid() IS NOT NULL
       AND auth.uid() IS DISTINCT FROM OLD.created_by THEN
        RAISE EXCEPTION 'Only the task creator or an administrator can change the task supervisor'
            USING ERRCODE = '42501';
    END IF;

    SELECT department.head_id INTO expected_supervisor_id
    FROM public.profiles AS creator
    LEFT JOIN public.departments AS department ON department.id = creator.department_id
    WHERE creator.id = NEW.created_by;

    IF NEW.supervisor_id IS DISTINCT FROM expected_supervisor_id THEN
        IF expected_supervisor_id IS NULL THEN
            RAISE EXCEPTION 'No department manager is assigned to the task creator' USING ERRCODE = '23514';
        END IF;
        RAISE EXCEPTION 'Selected supervisor must be the task creator''s department manager' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

COMMIT;
