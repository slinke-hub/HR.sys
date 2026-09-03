-- Ensure IT Manager is selectable for employees in the Administrative department.
-- This is idempotent and preserves any existing IT department title record.
BEGIN;

DO $$
DECLARE
  administrative_id uuid;
BEGIN
  SELECT id INTO administrative_id
  FROM public.departments
  WHERE lower(trim(name)) IN ('administrative', 'administration', 'administrative department')
  ORDER BY id
  LIMIT 1;

  IF administrative_id IS NULL THEN
    RAISE NOTICE 'Administrative department was not found; no job title changes made.';
    RETURN;
  END IF;

  INSERT INTO public.job_titles (name, department_id, is_active)
  SELECT 'IT Manager', administrative_id, true
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.job_titles
    WHERE lower(trim(name)) = 'it manager'
      AND department_id = administrative_id
  );

  UPDATE public.job_titles
  SET is_active = true
  WHERE lower(trim(name)) = 'it manager'
    AND department_id = administrative_id;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
