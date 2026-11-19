-- Consolidate exact duplicate department rows and add the Designing department.
-- The migration is idempotent and preserves references before removing duplicates.
BEGIN;

SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

DO $$
DECLARE
    duplicate_group record;
    keeper_id uuid;
    duplicate_id uuid;
    title_row record;
    table_row record;
BEGIN
    FOR duplicate_group IN
        SELECT regexp_replace(lower(BTRIM(name)), '\s+', ' ', 'g') AS normalized_name
        FROM public.departments
        WHERE NULLIF(BTRIM(name), '') IS NOT NULL
        GROUP BY regexp_replace(lower(BTRIM(name)), '\s+', ' ', 'g')
        HAVING COUNT(*) > 1
    LOOP
        SELECT department.id INTO keeper_id
        FROM public.departments department
        WHERE regexp_replace(lower(BTRIM(department.name)), '\s+', ' ', 'g') = duplicate_group.normalized_name
        ORDER BY COALESCE(department.is_active, TRUE) DESC, department.id
        LIMIT 1;

        FOR duplicate_id IN
            SELECT department.id
            FROM public.departments department
            WHERE regexp_replace(lower(BTRIM(department.name)), '\s+', ' ', 'g') = duplicate_group.normalized_name
              AND department.id <> keeper_id
        LOOP
            IF to_regclass('public.job_titles') IS NOT NULL THEN
                FOR title_row IN
                    SELECT title.id, title.name
                    FROM public.job_titles title
                    WHERE title.department_id = duplicate_id
                LOOP
                    IF EXISTS (
                        SELECT 1 FROM public.job_titles existing
                        WHERE existing.department_id = keeper_id
                          AND lower(BTRIM(existing.name)) = lower(BTRIM(title_row.name))
                    ) THEN
                        DELETE FROM public.job_titles WHERE id = title_row.id;
                    ELSE
                        UPDATE public.job_titles
                        SET department_id = keeper_id, is_active = TRUE
                        WHERE id = title_row.id;
                    END IF;
                END LOOP;
            END IF;

            FOR table_row IN
                SELECT DISTINCT columns.table_name
                FROM information_schema.columns columns
                JOIN information_schema.tables tables
                  ON tables.table_schema = columns.table_schema
                 AND tables.table_name = columns.table_name
                WHERE columns.table_schema = 'public'
                  AND columns.column_name = 'department_id'
                  AND tables.table_type = 'BASE TABLE'
                  AND columns.table_name NOT IN ('departments', 'job_titles')
            LOOP
                EXECUTE format(
                    'UPDATE public.%I SET department_id = $1 WHERE department_id = $2',
                    table_row.table_name
                ) USING keeper_id, duplicate_id;
            END LOOP;

            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'departments' AND column_name = 'parent_id'
            ) THEN
                UPDATE public.departments SET parent_id = keeper_id WHERE parent_id = duplicate_id;
            END IF;

            DELETE FROM public.departments WHERE id = duplicate_id;
        END LOOP;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1 FROM public.departments
        WHERE regexp_replace(lower(BTRIM(name)), '\s+', ' ', 'g') = 'designing'
    ) THEN
        INSERT INTO public.departments (name, description, is_active)
        VALUES ('Designing', 'Design and creative production.', TRUE);
    ELSE
        UPDATE public.departments
        SET is_active = TRUE
        WHERE regexp_replace(lower(BTRIM(name)), '\s+', ' ', 'g') = 'designing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'departments' AND column_name = 'name_ar'
    ) THEN
        EXECUTE $sql$
            UPDATE public.departments
            SET name_ar = 'التصميم'
            WHERE regexp_replace(lower(BTRIM(name)), '\s+', ' ', 'g') = 'designing'
        $sql$;
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
