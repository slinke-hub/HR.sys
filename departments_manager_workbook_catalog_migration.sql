-- Department manager catalog sourced from Departments_and_Job_Titles_Updated.xlsx.
-- Additive and idempotent: existing departments and employee assignments are preserved.
BEGIN;

ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TABLE IF NOT EXISTS public.job_titles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    name_ar TEXT,
    job_level TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (department_id, name)
);

ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS job_level TEXT;

WITH workbook_departments(name) AS (VALUES
    ('Administrative'), ('Marketing'), ('Sales'), ('IT'), ('Operations and Production')
)
INSERT INTO public.departments(name, is_active)
SELECT name, TRUE FROM workbook_departments
ON CONFLICT DO NOTHING;

UPDATE public.departments
SET is_active = TRUE
WHERE name IN ('Administrative', 'Marketing', 'Sales', 'IT', 'Operations and Production');

WITH catalog(department_name, job_level, title_name) AS (VALUES
    ('Administrative','Entry-Level','Receptionist'),
    ('Administrative','Entry-Level','Data Entry Clerk'),
    ('Administrative','Entry-Level','Administrative Assistant'),
    ('Administrative','Mid-Level','Office Manager'),
    ('Administrative','Mid-Level','Executive Assistant (EA)'),
    ('Administrative','Mid-Level','Facilities Coordinator'),
    ('Administrative','Leadership','Director of Administration'),
    ('Administrative','Leadership','Chief Administrative Officer (CAO)'),
    ('Marketing','Entry-Level','Marketing Coordinator'),
    ('Marketing','Entry-Level','Social Media Assistant'),
    ('Marketing','Mid-Level','Graphic Designer'),
    ('Marketing','Mid-Level','Social Media Manager'),
    ('Marketing','Mid-Level','SEO/SEM Specialist'),
    ('Marketing','Mid-Level','Content Strategist'),
    ('Marketing','Mid-Level','Product Marketing Manager'),
    ('Marketing','Leadership','Marketing Manager'),
    ('Marketing','Leadership','Director of Marketing'),
    ('Marketing','Leadership','Chief Marketing Officer (CMO)'),
    ('Sales','Entry-Level','Sales Development Representative (SDR)'),
    ('Sales','Entry-Level','Business Development Representative (BDR)'),
    ('Sales','Entry-Level','Sales Coordinator'),
    ('Sales','Mid-Level','Account Executive (AE)'),
    ('Sales','Mid-Level','Account Manager'),
    ('Sales','Mid-Level','Customer Success Manager'),
    ('Sales','Leadership','Sales Manager'),
    ('Sales','Leadership','Regional Sales Director'),
    ('Sales','Leadership','Vice President (VP) of Sales'),
    ('Sales','Leadership','Chief Revenue Officer (CRO)'),
    ('IT','Entry-Level','Helpdesk Technician'),
    ('IT','Entry-Level','Desktop Support Analyst'),
    ('IT','Entry-Level','IT Support Specialist'),
    ('IT','Mid-Level','Systems Administrator'),
    ('IT','Mid-Level','Network Engineer'),
    ('IT','Mid-Level','Database Administrator'),
    ('IT','Mid-Level','Cybersecurity Analyst'),
    ('IT','Mid-Level','Software Developer'),
    ('IT','Leadership','IT Manager'),
    ('IT','Leadership','Director of IT'),
    ('IT','Leadership','Chief Technology Officer (CTO)'),
    ('Operations and Production','Entry-Level','Operations Assistant'),
    ('Operations and Production','Entry-Level','Production Worker'),
    ('Operations and Production','Entry-Level','Logistics Coordinator'),
    ('Operations and Production','Mid-Level','Operations Analyst'),
    ('Operations and Production','Mid-Level','Quality Assurance (QA) Specialist'),
    ('Operations and Production','Mid-Level','Production Supervisor'),
    ('Operations and Production','Mid-Level','Supply Chain Manager'),
    ('Operations and Production','Leadership','Operations Manager'),
    ('Operations and Production','Leadership','Director of Operations'),
    ('Operations and Production','Leadership','Chief Operating Officer (COO)')
)
INSERT INTO public.job_titles(department_id, name, job_level, is_active)
SELECT department.id, catalog.title_name, catalog.job_level, TRUE
FROM catalog
JOIN public.departments department ON lower(department.name) = lower(catalog.department_name)
ON CONFLICT (department_id, name) DO UPDATE
SET job_level = EXCLUDED.job_level, is_active = TRUE;

NOTIFY pgrst, 'reload schema';
COMMIT;
