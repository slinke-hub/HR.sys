-- Merge Hospitality into Event Production & Operations without deleting history.
BEGIN;
SET LOCAL lock_timeout='15s';

DO $$
DECLARE event_department_id UUID; hospitality_department_id UUID;
BEGIN
    SELECT id INTO event_department_id FROM public.departments
    WHERE lower(name)=lower('Event Production & Operations') AND is_active=TRUE LIMIT 1;
    IF event_department_id IS NULL THEN RAISE EXCEPTION 'Event Production & Operations department was not found'; END IF;

    SELECT id INTO hospitality_department_id FROM public.departments
    WHERE lower(name)=lower('Hospitality') LIMIT 1;

    INSERT INTO public.job_titles(department_id,name,is_active) VALUES
        (event_department_id,'Hospitality Manager',TRUE),
        (event_department_id,'Barista',TRUE)
    ON CONFLICT(department_id,name) DO UPDATE SET is_active=TRUE;

    UPDATE public.profiles SET department_id=event_department_id,job_title='Barista'
    WHERE lower(BTRIM(COALESCE(job_title,''))) IN ('coffee corner','coffee corner manager');

    IF hospitality_department_id IS NOT NULL THEN
        UPDATE public.profiles SET department_id=event_department_id
        WHERE department_id=hospitality_department_id
          AND lower(BTRIM(COALESCE(job_title,'')))='hospitality manager';
        UPDATE public.departments SET is_active=FALSE WHERE id=hospitality_department_id;
        UPDATE public.job_titles SET is_active=FALSE WHERE department_id=hospitality_department_id;
    END IF;

    UPDATE public.tasks SET department='Event Production & Operations'
    WHERE lower(COALESCE(department,'')) ~ '(hospitality|coffee)';
END $$;

NOTIFY pgrst,'reload schema';
COMMIT;
