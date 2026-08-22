-- Move Technician from IT & Technical Support to Event Production & Operations.
-- Existing Technician employees, contracts and assigned tasks are reconciled.
BEGIN;

DO $$
DECLARE
    event_department_id UUID;
    it_department_id UUID;
BEGIN
    SELECT id INTO event_department_id
    FROM public.departments
    WHERE lower(name) = lower('Event Production & Operations') AND is_active = TRUE
    LIMIT 1;

    SELECT id INTO it_department_id
    FROM public.departments
    WHERE lower(name) = lower('IT & Technical Support')
    LIMIT 1;

    IF event_department_id IS NULL THEN
        RAISE EXCEPTION 'Event Production & Operations department was not found';
    END IF;

    INSERT INTO public.job_titles (department_id, name, is_active)
    VALUES (event_department_id, 'Technician', TRUE)
    ON CONFLICT (department_id, name) DO UPDATE SET is_active = TRUE;

    -- Contracts keep their employee link, but their displayed department follows
    -- the new canonical department before profiles are moved.
    UPDATE public.contracts contract
    SET department_id = event_department_id,
        department = 'Event Production & Operations',
        updated_at = NOW()
    FROM public.profiles profile
    WHERE contract.employee_id = profile.id
      AND lower(BTRIM(COALESCE(profile.job_title, ''))) = lower('Technician');

    UPDATE public.profiles
    SET department_id = event_department_id
    WHERE lower(BTRIM(COALESCE(job_title, ''))) = lower('Technician');

    UPDATE public.tasks task
    SET department = 'Event Production & Operations'
    FROM public.profiles profile
    WHERE task.assignee_id = profile.id
      AND lower(BTRIM(COALESCE(profile.job_title, ''))) = lower('Technician');

    IF it_department_id IS NOT NULL THEN
        UPDATE public.job_titles
        SET is_active = FALSE
        WHERE department_id = it_department_id
          AND lower(name) = lower('Technician');
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
