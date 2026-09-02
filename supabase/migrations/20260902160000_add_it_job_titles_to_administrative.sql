-- Ensure the standard IT titles are available when Administrative is selected.
BEGIN;
DO $$
DECLARE admin_id uuid; title_name text;
BEGIN
  SELECT id INTO admin_id FROM public.departments
  WHERE lower(trim(name)) IN ('administrative','administration','administrative department')
  ORDER BY id LIMIT 1;
  IF admin_id IS NULL THEN RETURN; END IF;
  FOREACH title_name IN ARRAY ARRAY['IT Manager','IT Support Specialist','System Administrator','Network Administrator','Technician'] LOOP
    IF NOT EXISTS (SELECT 1 FROM public.job_titles WHERE lower(trim(name)) = lower(title_name) AND department_id = admin_id) THEN
      INSERT INTO public.job_titles (name, department_id, is_active) VALUES (title_name, admin_id, true);
    END IF;
  END LOOP;
END $$;
NOTIFY pgrst, 'reload schema';
COMMIT;
