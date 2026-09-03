-- Merge IT into Administrative, preserve its users and job titles, then remove
-- the obsolete IT department row. This migration is safe to run repeatedly.
BEGIN;

DO $$
DECLARE
  admin_id uuid;
  it_id uuid;
  title_row record;
  table_row record;
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

  -- Move IT job titles first. If the same title already exists in
  -- Administrative, remove only the duplicate IT catalog row.
  FOR title_row IN
    SELECT jt.id, jt.name
    FROM public.job_titles jt
    WHERE jt.department_id = it_id
  LOOP
    IF EXISTS (
      SELECT 1 FROM public.job_titles existing
      WHERE existing.department_id = admin_id
        AND lower(trim(existing.name)) = lower(trim(title_row.name))
    ) THEN
      DELETE FROM public.job_titles WHERE id = title_row.id;
    ELSE
      UPDATE public.job_titles
      SET department_id = admin_id, is_active = true
      WHERE id = title_row.id;
    END IF;
  END LOOP;

  -- Reassign employees and every other department-scoped public table.
  FOR table_row IN
    SELECT DISTINCT table_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'department_id'
      AND table_name NOT IN ('departments', 'job_titles')
  LOOP
    EXECUTE format(
      'UPDATE public.%I SET department_id = $1 WHERE department_id = $2',
      table_row.table_name
    ) USING admin_id, it_id;
  END LOOP;

  -- Preserve department hierarchy links when supported.
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
