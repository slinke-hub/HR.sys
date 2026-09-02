-- Merge the IT department into Administrative. Employees, job titles and any
-- records carrying a department_id are reassigned before the old department
-- row is removed.
BEGIN;
DO $$
DECLARE
  admin_id uuid;
  it_id uuid;
  rec record;
BEGIN
  SELECT id INTO admin_id
  FROM public.departments
  WHERE lower(trim(name)) IN ('administrative', 'administration', 'administrative department')
  ORDER BY id LIMIT 1;

  SELECT id INTO it_id
  FROM public.departments
  WHERE lower(trim(name)) IN ('it', 'it department', 'information technology')
  ORDER BY id LIMIT 1;

  IF admin_id IS NULL OR it_id IS NULL OR admin_id = it_id THEN
    RETURN;
  END IF;

  -- Reassign every public table whose department_id points at departments.
  FOR rec IN
    SELECT DISTINCT table_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'department_id'
      AND table_name <> 'departments'
  LOOP
    EXECUTE format(
      'UPDATE public.%I SET department_id = $1 WHERE department_id = $2',
      rec.table_name
    ) USING admin_id, it_id;
  END LOOP;

  -- Preserve hierarchy links if the departments table has a parent_id column.
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'departments' AND column_name = 'parent_id'
  ) THEN
    UPDATE public.departments SET parent_id = admin_id WHERE parent_id = it_id;
  END IF;

  DELETE FROM public.departments WHERE id = it_id;
END $$;
NOTIFY pgrst, 'reload schema';
COMMIT;
