-- Keep strict titles for catalog departments while allowing new custom departments.
BEGIN;

CREATE OR REPLACE FUNCTION public.validate_profile_job_title() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    IF TG_OP='UPDATE' AND NEW.job_title IS NOT DISTINCT FROM OLD.job_title AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id THEN RETURN NEW; END IF;
    IF NULLIF(BTRIM(COALESCE(NEW.job_title,'')),'') IS NULL THEN RETURN NEW; END IF;

    -- A department with catalog titles must use one of its active titles.
    IF NEW.department_id IS NOT NULL AND EXISTS(
        SELECT 1 FROM public.job_titles WHERE is_active=TRUE AND department_id=NEW.department_id
    ) THEN
        IF NOT EXISTS(
            SELECT 1 FROM public.job_titles
            WHERE is_active=TRUE AND department_id=NEW.department_id
              AND lower(name)=lower(BTRIM(NEW.job_title))
        ) THEN RAISE EXCEPTION 'The selected job title does not belong to the selected department'; END IF;
        RETURN NEW;
    END IF;

    -- Custom departments without a title catalog retain the employee's title.
    IF NEW.department_id IS NOT NULL THEN RETURN NEW; END IF;

    IF NOT EXISTS(SELECT 1 FROM public.job_titles WHERE is_active=TRUE AND lower(name)=lower(BTRIM(NEW.job_title))) THEN
        RAISE EXCEPTION 'Please select an active job title from the company catalog';
    END IF;
    RETURN NEW;
END; $$;

NOTIFY pgrst,'reload schema';
COMMIT;
