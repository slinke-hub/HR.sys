-- Reconcile the live system to the final approved department/title catalog.
-- Historical departments/titles are archived, never deleted.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
DO $$ BEGIN PERFORM pg_advisory_xact_lock(hashtext('muqam_hr_final_department_catalog')); END $$;

ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TABLE IF NOT EXISTS public.job_titles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(department_id,name)
);

WITH required(name,description) AS (VALUES
('Executive & Administrative','Executive leadership, HR and finance.'),
('Event Production & Operations','Event delivery, operations, logistics, procurement, client operations and hospitality.'),
('Marketing & Sales','Marketing, sales and creative production.'),
('IT & Technical Support','Technology administration, support, AV and technical services.')
)
INSERT INTO public.departments(name,description,is_active)
SELECT required.name,required.description,TRUE FROM required
WHERE NOT EXISTS(SELECT 1 FROM public.departments department WHERE lower(department.name)=lower(required.name));

UPDATE public.departments SET is_active=TRUE WHERE lower(name) IN (
 lower('Executive & Administrative'),lower('Event Production & Operations'),
 lower('Marketing & Sales'),lower('IT & Technical Support')
);

WITH catalog(department_name,title_name) AS (VALUES
('Executive & Administrative','General Manager'),('Executive & Administrative','HR Manager'),
('Executive & Administrative','Finance Manager'),('Executive & Administrative','Accountant'),
('Event Production & Operations','Event Manager'),('Event Production & Operations','Event Coordinator'),
('Event Production & Operations','Operations Manager'),('Event Production & Operations','Warehouse Manager'),
('Event Production & Operations','Logistics Coordinator'),('Event Production & Operations','Procurement Officer'),
('Event Production & Operations','Client Account Manager'),('Event Production & Operations','Barista'),
('Marketing & Sales','Marketing Manager'),('Marketing & Sales','Marketing Representative'),
('Marketing & Sales','Sales Supervisor'),('Marketing & Sales','Sales Representative'),
('Marketing & Sales','Graphic Designer'),('Marketing & Sales','Photographer'),
('IT & Technical Support','IT Administrator'),('IT & Technical Support','IT Support'),
('IT & Technical Support','Audio-Visual (AV) Specialist'),('IT & Technical Support','Technician')
)
INSERT INTO public.job_titles(department_id,name,is_active)
SELECT department.id,catalog.title_name,TRUE
FROM catalog JOIN public.departments department ON lower(department.name)=lower(catalog.department_name)
ON CONFLICT(department_id,name) DO UPDATE SET is_active=TRUE;

-- Normalize only legacy titles with an unambiguous successor, changing the
-- title and department atomically so catalog validation remains satisfied.
WITH title_mapping(old_title,new_title,department_name) AS (VALUES
('executive & administrative manager','General Manager','Executive & Administrative'),
('event production & operations manager','Operations Manager','Event Production & Operations'),
('marketing & sales manager','Marketing Manager','Marketing & Sales'),
('it & technical support manager','IT Administrator','IT & Technical Support'),
('hospitality manager','Barista','Event Production & Operations'),
('coffee corner manager','Barista','Event Production & Operations'),
('coffee corner','Barista','Event Production & Operations')
)
UPDATE public.profiles profile SET job_title=title_mapping.new_title,department_id=department.id
FROM title_mapping JOIN public.departments department ON lower(department.name)=lower(title_mapping.department_name)
WHERE lower(BTRIM(COALESCE(profile.job_title,'')))=title_mapping.old_title;

-- A final-catalog title determines its employee department without changing managers.
UPDATE public.profiles profile SET department_id=title.department_id
FROM public.job_titles title JOIN public.departments department ON department.id=title.department_id
WHERE title.is_active=TRUE AND department.is_active=TRUE
  AND lower(BTRIM(COALESCE(profile.job_title,'')))=lower(title.name)
  AND lower(department.name) IN (
      lower('Executive & Administrative'),lower('Event Production & Operations'),
      lower('Marketing & Sales'),lower('IT & Technical Support')
  );

-- Only the exact approved catalog remains selectable.
UPDATE public.job_titles title SET is_active=FALSE
WHERE NOT EXISTS (
    SELECT 1 FROM public.departments department WHERE department.id=title.department_id AND department.is_active=TRUE AND (
      (department.name='Executive & Administrative' AND title.name IN ('General Manager','HR Manager','Finance Manager','Accountant')) OR
      (department.name='Event Production & Operations' AND title.name IN ('Event Manager','Event Coordinator','Operations Manager','Warehouse Manager','Logistics Coordinator','Procurement Officer','Client Account Manager','Barista')) OR
      (department.name='Marketing & Sales' AND title.name IN ('Marketing Manager','Marketing Representative','Sales Supervisor','Sales Representative','Graphic Designer','Photographer')) OR
      (department.name='IT & Technical Support' AND title.name IN ('IT Administrator','IT Support','Audio-Visual (AV) Specialist','Technician'))
    )
);

UPDATE public.departments SET is_active=FALSE WHERE lower(name) NOT IN (
 lower('Executive & Administrative'),lower('Event Production & Operations'),
 lower('Marketing & Sales'),lower('IT & Technical Support')
);

-- Preserve task assignment IDs; only synchronize their department label.
UPDATE public.tasks task SET department=department.name
FROM public.profiles profile JOIN public.departments department ON department.id=profile.department_id
WHERE task.assignee_id=profile.id AND department.is_active=TRUE
  AND task.department IS DISTINCT FROM department.name;

UPDATE public.tasks SET department=CASE
    WHEN lower(department) ~ '(marketing|sales|design)' THEN 'Marketing & Sales'
    WHEN lower(department) ~ '(event|production|operation|warehouse|logistic|procurement|client|hospitality|coffee)' THEN 'Event Production & Operations'
    WHEN lower(department) ~ '(^it$|technical|audio|visual)' THEN 'IT & Technical Support'
    WHEN lower(department) ~ '(executive|admin|human resource|^hr$|finance|account)' THEN 'Executive & Administrative'
    ELSE department END
WHERE department IS NOT NULL;

-- Rebuild approval heads from approved titles, with an Operations fallback.
WITH candidates AS (
 SELECT department.id department_id,profile.id profile_id,
 row_number() OVER(PARTITION BY department.id ORDER BY
   CASE profile.job_title WHEN 'Event Manager' THEN 1 WHEN 'Operations Manager' THEN 2 ELSE 1 END,
   profile.created_at) position
 FROM public.departments department JOIN public.profiles profile ON profile.department_id=department.id
 WHERE department.is_active=TRUE AND (
   (department.name='Executive & Administrative' AND profile.job_title='General Manager') OR
   (department.name='Event Production & Operations' AND profile.job_title IN ('Event Manager','Operations Manager')) OR
   (department.name='Marketing & Sales' AND profile.job_title='Marketing Manager') OR
   (department.name='IT & Technical Support' AND profile.job_title='IT Administrator')
 )
)
UPDATE public.departments department SET head_id=candidates.profile_id
FROM candidates WHERE candidates.department_id=department.id AND candidates.position=1;

ALTER TABLE public.job_titles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS job_titles_authenticated_select ON public.job_titles;
CREATE POLICY job_titles_authenticated_select ON public.job_titles FOR SELECT TO authenticated USING(is_active=TRUE);
GRANT SELECT ON public.job_titles TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
