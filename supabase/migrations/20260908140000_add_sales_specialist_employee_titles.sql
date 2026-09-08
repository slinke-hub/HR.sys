-- Add the requested Sales department job titles in both interface languages.
BEGIN;

ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS name_ar TEXT;
ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS job_level TEXT;

DO $$
DECLARE
    sales_department RECORD;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.departments department
        WHERE LOWER(BTRIM(COALESCE(department.name, ''))) = 'sales'
           OR BTRIM(COALESCE(department.name_ar, '')) = 'المبيعات'
    ) THEN
        RAISE EXCEPTION 'Sales department was not found';
    END IF;

    FOR sales_department IN
        SELECT department.id
        FROM public.departments department
        WHERE LOWER(BTRIM(COALESCE(department.name, ''))) = 'sales'
           OR BTRIM(COALESCE(department.name_ar, '')) = 'المبيعات'
    LOOP
        INSERT INTO public.job_titles (department_id, name, name_ar, job_level, is_active)
        SELECT sales_department.id, title.name, title.name_ar, title.job_level, TRUE
        FROM (VALUES
            ('Sales Specialist', 'أخصائي مبيعات', 'Mid-Level'),
            ('Sales Employee', 'موظف مبيعات', 'Entry-Level')
        ) AS title(name, name_ar, job_level)
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.job_titles existing
            WHERE existing.department_id = sales_department.id
              AND LOWER(BTRIM(existing.name)) = LOWER(BTRIM(title.name))
        );

        UPDATE public.job_titles existing
        SET name_ar = CASE LOWER(BTRIM(existing.name))
                WHEN 'sales specialist' THEN 'أخصائي مبيعات'
                WHEN 'sales employee' THEN 'موظف مبيعات'
            END,
            job_level = CASE LOWER(BTRIM(existing.name))
                WHEN 'sales specialist' THEN 'Mid-Level'
                WHEN 'sales employee' THEN 'Entry-Level'
            END,
            is_active = TRUE
        WHERE existing.department_id = sales_department.id
          AND LOWER(BTRIM(existing.name)) IN ('sales specialist', 'sales employee');
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
