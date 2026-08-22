-- Add the finance function's job titles to Executive & Administrative.
-- The standalone legacy Finance department remains inactive.
BEGIN;

CREATE TABLE IF NOT EXISTS public.job_titles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(department_id, name)
);

WITH executive AS (
    SELECT id
    FROM public.departments
    WHERE LOWER(BTRIM(name)) = LOWER('Executive & Administrative')
    ORDER BY created_at
    LIMIT 1
), finance_titles(name) AS (
    VALUES
        ('Senior Financial Analyst'),
        ('Senior Accountant'),
        ('Internal Auditor'),
        ('Staff Accountant / Junior Accountant'),
        ('Bookkeeper'),
        ('Payroll Clerk / Specialist')
)
INSERT INTO public.job_titles(department_id, name, is_active)
SELECT executive.id, finance_titles.name, TRUE
FROM executive CROSS JOIN finance_titles
ON CONFLICT(department_id, name) DO UPDATE SET is_active = TRUE;

UPDATE public.departments
SET is_active = FALSE
WHERE LOWER(BTRIM(name)) = 'finance';

COMMIT;
