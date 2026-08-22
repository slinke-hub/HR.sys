-- Consolidate the legacy standalone Finance department into
-- Executive & Administrative without losing employee or contract links.
BEGIN;

ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

DO $$
DECLARE
    executive_id UUID;
    finance_ids UUID[];
BEGIN
    SELECT id INTO executive_id
    FROM public.departments
    WHERE LOWER(BTRIM(name)) = LOWER('Executive & Administrative')
    ORDER BY created_at
    LIMIT 1;

    IF executive_id IS NULL THEN
        RAISE EXCEPTION 'Executive & Administrative department does not exist';
    END IF;

    SELECT ARRAY_AGG(id) INTO finance_ids
    FROM public.departments
    WHERE LOWER(BTRIM(name)) = 'finance'
      AND id <> executive_id;

    IF finance_ids IS NULL THEN RETURN; END IF;

    UPDATE public.profiles
       SET department_id = executive_id
     WHERE department_id = ANY(finance_ids);

    IF to_regclass('public.job_titles') IS NOT NULL THEN
        UPDATE public.job_titles
           SET is_active = FALSE
         WHERE department_id = ANY(finance_ids);

        INSERT INTO public.job_titles(department_id, name, is_active)
        VALUES (executive_id, 'Finance Manager', TRUE),
               (executive_id, 'Accountant', TRUE)
        ON CONFLICT(department_id, name) DO UPDATE SET is_active = TRUE;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='contracts' AND column_name='department_id'
    ) THEN
        EXECUTE 'UPDATE public.contracts SET department_id=$1, department=$2 WHERE department_id=ANY($3)'
        USING executive_id, 'Executive & Administrative', finance_ids;
    END IF;

    UPDATE public.tasks
       SET department = 'Executive & Administrative'
     WHERE LOWER(BTRIM(COALESCE(department, ''))) = 'finance';

    UPDATE public.departments
       SET is_active = FALSE,
           head_id = NULL
     WHERE id = ANY(finance_ids);
END $$;

COMMIT;
