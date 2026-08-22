-- Add Finance as a canonical department and move every finance job title,
-- employee, contract and assigned task out of Executive & Administrative.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TABLE IF NOT EXISTS public.job_titles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (department_id, name)
);

DO $$
DECLARE
    finance_department_id UUID;
    executive_department_id UUID;
    finance_titles TEXT[] := ARRAY[
        'Finance Manager', 'Accountant', 'Senior Financial Analyst',
        'Senior Accountant', 'Internal Auditor',
        'Staff Accountant / Junior Accountant', 'Bookkeeper',
        'Payroll Clerk / Specialist'
    ];
BEGIN
    SELECT id INTO finance_department_id
    FROM public.departments
    WHERE LOWER(BTRIM(name)) = LOWER('Finance')
    ORDER BY is_active DESC, created_at
    LIMIT 1;

    IF finance_department_id IS NULL THEN
        INSERT INTO public.departments (name, description, is_active)
        VALUES ('Finance', 'Financial management, accounting, audit, bookkeeping and payroll.', TRUE)
        RETURNING id INTO finance_department_id;
    ELSE
        UPDATE public.departments
        SET name = 'Finance',
            description = 'Financial management, accounting, audit, bookkeeping and payroll.',
            is_active = TRUE
        WHERE id = finance_department_id;
    END IF;

    -- Prevent duplicate legacy Finance rows from appearing in dropdowns.
    UPDATE public.departments
    SET is_active = FALSE, head_id = NULL
    WHERE LOWER(BTRIM(name)) = LOWER('Finance')
      AND id <> finance_department_id;

    UPDATE public.job_titles title
    SET is_active = FALSE
    FROM public.departments department
    WHERE title.department_id = department.id
      AND LOWER(BTRIM(department.name)) = LOWER('Finance')
      AND department.id <> finance_department_id;

    SELECT id INTO executive_department_id
    FROM public.departments
    WHERE LOWER(BTRIM(name)) = LOWER('Executive & Administrative')
    ORDER BY is_active DESC, created_at
    LIMIT 1;

    INSERT INTO public.job_titles (department_id, name, is_active)
    SELECT finance_department_id, title, TRUE FROM unnest(finance_titles) AS title
    ON CONFLICT (department_id, name) DO UPDATE SET is_active = TRUE;

    -- Move employees first. The profile validation trigger accepts the move
    -- because the matching Finance titles were inserted above.
    UPDATE public.profiles
    SET department_id = finance_department_id
    WHERE LOWER(BTRIM(COALESCE(job_title, ''))) = ANY (
        SELECT LOWER(title) FROM unnest(finance_titles) AS title
    );

    -- Keep contract department metadata synchronized where those columns exist.
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='contracts' AND column_name='department_id') THEN
        EXECUTE $sql$
            UPDATE public.contracts contract
            SET department_id = $1
            FROM public.profiles profile
            WHERE contract.employee_id = profile.id
              AND LOWER(BTRIM(COALESCE(profile.job_title, ''))) = ANY ($2)
        $sql$ USING finance_department_id, ARRAY(SELECT LOWER(title) FROM unnest(finance_titles) AS title);
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='contracts' AND column_name='department') THEN
        EXECUTE $sql$
            UPDATE public.contracts contract
            SET department = 'Finance'
            FROM public.profiles profile
            WHERE contract.employee_id = profile.id
              AND LOWER(BTRIM(COALESCE(profile.job_title, ''))) = ANY ($1)
        $sql$ USING ARRAY(SELECT LOWER(title) FROM unnest(finance_titles) AS title);
    END IF;

    UPDATE public.tasks task
    SET department = 'Finance'
    FROM public.profiles profile
    WHERE task.assignee_id = profile.id
      AND LOWER(BTRIM(COALESCE(profile.job_title, ''))) = ANY (
          SELECT LOWER(title) FROM unnest(finance_titles) AS title
      );

    UPDATE public.tasks
    SET department = 'Finance'
    WHERE LOWER(BTRIM(COALESCE(department, ''))) ~ '(finance|account|bookkeep|payroll|audit)';

    -- The titles no longer appear under Executive & Administrative.
    IF executive_department_id IS NOT NULL THEN
        UPDATE public.job_titles
        SET is_active = FALSE
        WHERE department_id = executive_department_id
          AND LOWER(name) = ANY (SELECT LOWER(title) FROM unnest(finance_titles) AS title);
    END IF;

    -- Finance Manager becomes the Finance department approval head when one exists.
    UPDATE public.departments department
    SET head_id = candidate.id
    FROM LATERAL (
        SELECT profile.id
        FROM public.profiles profile
        WHERE profile.department_id = finance_department_id
          AND LOWER(BTRIM(COALESCE(profile.job_title, ''))) = LOWER('Finance Manager')
        ORDER BY profile.created_at
        LIMIT 1
    ) candidate
    WHERE department.id = finance_department_id;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
