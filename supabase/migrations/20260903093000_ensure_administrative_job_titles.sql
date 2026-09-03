-- Ensure the complete Administrative job-title catalog is available.
-- Idempotent: existing records are preserved and only missing titles are added.
BEGIN;

DO $$
DECLARE
  administrative_id uuid;
  title_name text;
BEGIN
  SELECT id INTO administrative_id
  FROM public.departments
  WHERE lower(trim(name)) IN ('administrative', 'administration', 'administrative department')
  ORDER BY id
  LIMIT 1;

  IF administrative_id IS NULL THEN
    RAISE NOTICE 'Administrative department was not found; no job titles added.';
    RETURN;
  END IF;

  FOREACH title_name IN ARRAY ARRAY[
    'Owner', 'GM', 'Accountant Manager', 'CEO', 'HR Manager',
    'Accountant Assistant', 'Receptionist', 'Data Entry Clerk',
    'Administrative Assistant', 'Office Manager', 'Executive Assistant (EA)',
    'Facilities Coordinator', 'Director of Administration',
    'Chief Administrative Officer (CAO)', 'IT Manager',
    'IT Support Specialist', 'System Administrator', 'Network Administrator',
    'Technician'
  ] LOOP
    INSERT INTO public.job_titles (name, department_id, is_active)
    SELECT title_name, administrative_id, true
    WHERE NOT EXISTS (
      SELECT 1 FROM public.job_titles
      WHERE lower(trim(name)) = lower(trim(title_name))
        AND department_id = administrative_id
    );
  END LOOP;

  UPDATE public.job_titles
  SET is_active = true
  WHERE department_id = administrative_id
    AND lower(trim(name)) IN (
      'owner', 'gm', 'accountant manager', 'ceo', 'hr manager',
      'accountant assistant', 'receptionist', 'data entry clerk',
      'administrative assistant', 'office manager', 'executive assistant (ea)',
      'facilities coordinator', 'director of administration',
      'chief administrative officer (cao)', 'it manager',
      'it support specialist', 'system administrator', 'network administrator',
      'technician'
    );
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
