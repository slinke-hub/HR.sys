-- Consolidate the duplicate Administration department into Administrative.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS name_ar TEXT;
ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS job_level TEXT;

DO $$
DECLARE
    target_id UUID;
    target_head UUID;
    source_head UUID;
    source_ids UUID[];
BEGIN
    SELECT id,head_id INTO target_id,target_head
    FROM public.departments
    WHERE lower(btrim(name))='administrative'
    ORDER BY is_active DESC NULLS LAST
    LIMIT 1;

    IF target_id IS NULL THEN
        INSERT INTO public.departments(name,is_active) VALUES('Administrative',TRUE)
        RETURNING id INTO target_id;
    END IF;

    SELECT array_agg(id) INTO source_ids
    FROM public.departments
    WHERE lower(btrim(name))='administration' AND id<>target_id;

    IF COALESCE(array_length(source_ids,1),0)=0 THEN
        UPDATE public.departments SET is_active=TRUE WHERE id=target_id;
        RETURN;
    END IF;

    SELECT head_id INTO source_head FROM public.departments
    WHERE id=ANY(source_ids) AND head_id IS NOT NULL LIMIT 1;

    INSERT INTO public.job_titles(department_id,name,name_ar,job_level,is_active)
    SELECT target_id,title.name,title.name_ar,title.job_level,title.is_active
    FROM public.job_titles title
    WHERE title.department_id=ANY(source_ids)
    ON CONFLICT(department_id,name) DO UPDATE SET
        name_ar=COALESCE(EXCLUDED.name_ar,public.job_titles.name_ar),
        job_level=COALESCE(EXCLUDED.job_level,public.job_titles.job_level),
        is_active=public.job_titles.is_active OR EXCLUDED.is_active;

    UPDATE public.profiles SET department_id=target_id WHERE department_id=ANY(source_ids);
    UPDATE public.tasks SET department='Administrative'
    WHERE lower(btrim(COALESCE(department,'')))='administration';

    IF target_head IS NULL AND source_head IS NOT NULL THEN
        UPDATE public.departments SET head_id=source_head WHERE id=target_id;
    END IF;

    UPDATE public.job_titles SET is_active=FALSE WHERE department_id=ANY(source_ids);
    UPDATE public.departments SET is_active=FALSE WHERE id=ANY(source_ids);
    UPDATE public.departments SET is_active=TRUE WHERE id=target_id;
END $$;

NOTIFY pgrst,'reload schema';
COMMIT;
