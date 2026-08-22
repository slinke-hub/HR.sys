-- Canonical department and job-title catalog.
-- Legacy departments are archived, never deleted, so historical references remain valid.
BEGIN;

-- Run this catalog migration one session at a time. The bounded timeout avoids
-- waiting indefinitely when another dashboard request or migration holds a lock.
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';
DO $$ BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('muqam_hr_canonical_department_catalog'));
END $$;

-- Follow the application's normal write order (employee/task data first, then
-- department metadata) before mixing schema and data updates.
LOCK TABLE public.profiles IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.tasks IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.departments IN ACCESS EXCLUSIVE MODE;

ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TABLE IF NOT EXISTS public.job_titles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(department_id,name)
);

WITH canonical(name,description) AS (VALUES
('Executive & Administrative','Executive leadership and people operations.'),
('Finance','Financial management, accounting, audit, bookkeeping and payroll.'),
('Event Production & Operations','Event delivery, operations, logistics, procurement and client operations.'),
('Marketing & Sales','Marketing, sales and creative production.'),
('IT & Technical Support','Technology administration, technical support and AV services.')
)
INSERT INTO public.departments(name,description,is_active)
SELECT c.name,c.description,TRUE FROM canonical c
WHERE NOT EXISTS(SELECT 1 FROM public.departments d WHERE lower(d.name)=lower(c.name));

UPDATE public.departments SET is_active=TRUE WHERE lower(name) IN (
 lower('Executive & Administrative'),lower('Finance'),lower('Event Production & Operations'),
 lower('Marketing & Sales'),lower('IT & Technical Support')
);

WITH catalog(department_name,title_name) AS (VALUES
('Executive & Administrative','General Manager'),('Executive & Administrative','HR Manager'),
('Finance','Finance Manager'),('Finance','Accountant'),
('Finance','Senior Financial Analyst'),('Finance','Senior Accountant'),
('Finance','Internal Auditor'),('Finance','Staff Accountant / Junior Accountant'),
('Finance','Bookkeeper'),('Finance','Payroll Clerk / Specialist'),
('Event Production & Operations','Event Manager'),('Event Production & Operations','Event Coordinator'),
('Event Production & Operations','Operations Manager'),('Event Production & Operations','Warehouse Manager'),
('Event Production & Operations','Logistics Coordinator'),('Event Production & Operations','Procurement Officer'),
('Event Production & Operations','Client Account Manager'),
('Event Production & Operations','Barista'),('Event Production & Operations','Technician'),
('Marketing & Sales','Marketing Manager'),('Marketing & Sales','Marketing Representative'),
('Marketing & Sales','Sales Supervisor'),('Marketing & Sales','Sales Representative'),
('Marketing & Sales','Graphic Designer'),('Marketing & Sales','Photographer'),
('IT & Technical Support','IT Administrator'),('IT & Technical Support','IT Support'),
('IT & Technical Support','Audio-Visual (AV) Specialist')
)
INSERT INTO public.job_titles(department_id,name,is_active)
SELECT d.id,c.title_name,TRUE FROM catalog c JOIN public.departments d ON lower(d.name)=lower(c.department_name)
ON CONFLICT(department_id,name) DO UPDATE SET is_active=TRUE;

UPDATE public.job_titles title SET is_active=FALSE
FROM public.departments department
WHERE title.department_id=department.id
  AND department.name='Executive & Administrative'
  AND title.name IN ('Finance Manager','Accountant','Senior Financial Analyst','Senior Accountant','Internal Auditor','Staff Accountant / Junior Accountant','Bookkeeper','Payroll Clerk / Specialist');

-- A recognized title is authoritative for the employee's canonical department.
UPDATE public.profiles p SET department_id=jt.department_id
FROM public.job_titles jt JOIN public.departments catalog_department ON catalog_department.id=jt.department_id
WHERE jt.is_active=TRUE AND lower(BTRIM(COALESCE(p.job_title,'')))=lower(jt.name)
  AND lower(catalog_department.name) IN (
      lower('Executive & Administrative'),lower('Finance'),lower('Event Production & Operations'),
      lower('Marketing & Sales'),lower('IT & Technical Support')
  );

-- Assign department heads from the manager titles where those employees exist.
WITH head_candidates AS (
    SELECT d.id department_id,p.id manager_id,
           row_number() OVER(PARTITION BY d.id ORDER BY CASE p.job_title WHEN 'Event Manager' THEN 1 ELSE 2 END) position
    FROM public.departments d JOIN public.profiles p ON p.department_id=d.id
    WHERE d.is_active=TRUE AND (
        (d.name='Executive & Administrative' AND p.job_title='General Manager') OR
        (d.name='Finance' AND p.job_title='Finance Manager') OR
        (d.name='Event Production & Operations' AND p.job_title IN ('Event Manager','Operations Manager')) OR
        (d.name='Marketing & Sales' AND p.job_title='Marketing Manager') OR
        (d.name='IT & Technical Support' AND p.job_title='IT Administrator')
    )
)
UPDATE public.departments d SET head_id=c.manager_id
FROM head_candidates c WHERE c.department_id=d.id AND c.position=1;

-- Keep task department text aligned with the assignee's canonical department.
UPDATE public.tasks task SET department=department.name
FROM public.profiles profile JOIN public.departments department ON department.id=profile.department_id
WHERE task.assignee_id=profile.id AND department.is_active=TRUE
  AND task.department IS DISTINCT FROM department.name;

-- Map remaining historical task labels even when the old task has no assignee.
UPDATE public.tasks SET department=CASE
    WHEN lower(department) ~ '(marketing|sales|design)' THEN 'Marketing & Sales'
    WHEN lower(department) ~ '(event|production|operation|warehouse|logistic|procurement|client|hospitality|coffee)' THEN 'Event Production & Operations'
    WHEN lower(department) ~ '(^it$|technical|audio|visual)' THEN 'IT & Technical Support'
    WHEN lower(department) ~ '(finance|account|bookkeep|payroll|audit)' THEN 'Finance'
    WHEN lower(department) ~ '(executive|admin|human resource|^hr$)' THEN 'Executive & Administrative'
    ELSE department END
WHERE department IS NOT NULL;

-- Archive every legacy department after employees have been safely reassigned.
UPDATE public.departments SET is_active=FALSE
WHERE lower(name) NOT IN (
 lower('Executive & Administrative'),lower('Finance'),lower('Event Production & Operations'),
 lower('Marketing & Sales'),lower('IT & Technical Support')
);

ALTER TABLE public.job_titles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS job_titles_authenticated_select ON public.job_titles;
CREATE POLICY job_titles_authenticated_select ON public.job_titles FOR SELECT TO authenticated USING(is_active=TRUE);
GRANT SELECT ON public.job_titles TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_profile_job_title() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
    IF TG_OP='UPDATE' AND NEW.job_title IS NOT DISTINCT FROM OLD.job_title AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id THEN RETURN NEW; END IF;
    IF NULLIF(BTRIM(COALESCE(NEW.job_title,'')),'') IS NULL THEN RETURN NEW; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.job_titles WHERE is_active=TRUE AND lower(name)=lower(BTRIM(NEW.job_title))) THEN
        RAISE EXCEPTION 'Please select an active job title from the company catalog';
    END IF;
    IF NEW.department_id IS NOT NULL AND NOT EXISTS(
        SELECT 1 FROM public.job_titles WHERE is_active=TRUE AND department_id=NEW.department_id AND lower(name)=lower(BTRIM(NEW.job_title))
    ) THEN RAISE EXCEPTION 'The selected job title does not belong to the selected department'; END IF;
    RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS validate_profile_job_title_trigger ON public.profiles;
CREATE TRIGGER validate_profile_job_title_trigger BEFORE INSERT OR UPDATE OF job_title,department_id ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.validate_profile_job_title();

NOTIFY pgrst,'reload schema';
COMMIT;
