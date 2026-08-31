-- Add the Owner job title to the Administrative department.
BEGIN;

INSERT INTO public.job_titles (department_id, name, is_active)
SELECT d.id, 'Owner', TRUE
FROM public.departments d
WHERE lower(trim(d.name)) IN ('administrative', 'executive & administrative')
  AND NOT EXISTS (
    SELECT 1 FROM public.job_titles jt
    WHERE jt.department_id = d.id AND lower(trim(jt.name)) = 'owner'
  );

UPDATE public.job_titles jt
SET is_active = TRUE
FROM public.departments d
WHERE jt.department_id = d.id
  AND lower(trim(d.name)) IN ('administrative', 'executive & administrative')
  AND lower(trim(jt.name)) = 'owner';

NOTIFY pgrst, 'reload schema';
COMMIT;
