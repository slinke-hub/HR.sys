-- Allow Technician in Event Production & Operations as well as IT & Technical Support.
BEGIN;
INSERT INTO public.job_titles(department_id,name,is_active)
SELECT id,'Technician',TRUE FROM public.departments
WHERE lower(name)=lower('Event Production & Operations')
ON CONFLICT(department_id,name) DO UPDATE SET is_active=TRUE;
NOTIFY pgrst,'reload schema';
COMMIT;
