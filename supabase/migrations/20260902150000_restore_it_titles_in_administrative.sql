-- Restore orphaned IT job titles under Administrative in databases where the
-- old IT department was removed with ON DELETE SET NULL.
BEGIN;
UPDATE public.job_titles
SET department_id = (
  SELECT id FROM public.departments
  WHERE lower(trim(name)) IN ('administrative', 'administration', 'administrative department')
  ORDER BY id LIMIT 1
)
WHERE department_id IS NULL
  AND is_active IS DISTINCT FROM false
  AND (
    name ILIKE 'IT%'
    OR name ILIKE 'Information Technology%'
    OR name ILIKE 'System%'
    OR name ILIKE 'Network%'
    OR name ILIKE 'Technical%'
    OR name ILIKE 'Technician%'
    OR name ILIKE 'Developer%'
    OR name ILIKE 'Software%'
    OR name ILIKE 'Support%'
  )
  AND EXISTS (SELECT 1 FROM public.departments WHERE lower(trim(name)) IN ('administrative', 'administration', 'administrative department'));
NOTIFY pgrst, 'reload schema';
COMMIT;
