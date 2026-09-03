-- Repair IT titles for every Administrative department variant.
-- This handles installations that contain both "Administration" and
-- "Administrative" rows and is safe to run repeatedly.
BEGIN;

DO $$
DECLARE
  department_row record;
  title_name text;
BEGIN
  FOR department_row IN
    SELECT id
    FROM public.departments
    WHERE lower(trim(name)) IN ('administrative', 'administration', 'administrative department')
  LOOP
    FOREACH title_name IN ARRAY ARRAY[
      'IT Manager', 'IT Support Specialist', 'System Administrator',
      'Network Administrator', 'Technician'
    ] LOOP
      INSERT INTO public.job_titles (name, department_id, is_active)
      SELECT title_name, department_row.id, true
      WHERE NOT EXISTS (
        SELECT 1 FROM public.job_titles
        WHERE lower(trim(name)) = lower(trim(title_name))
          AND department_id = department_row.id
      );

      UPDATE public.job_titles
      SET is_active = true
      WHERE department_id = department_row.id
        AND lower(trim(name)) = lower(trim(title_name));
    END LOOP;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
