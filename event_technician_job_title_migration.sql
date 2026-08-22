-- Technician belongs exclusively to Event Production & Operations.
BEGIN;
INSERT INTO public.job_titles(department_id,name,is_active)
SELECT id,'Technician',TRUE FROM public.departments
WHERE lower(name)=lower('Event Production & Operations')
ON CONFLICT(department_id,name) DO UPDATE SET is_active=TRUE;
UPDATE public.job_titles title SET is_active=FALSE
FROM public.departments department
WHERE title.department_id=department.id
  AND lower(department.name)=lower('IT & Technical Support')
  AND lower(title.name)=lower('Technician');
NOTIFY pgrst,'reload schema';
COMMIT;
