-- Remove duplicate active departments/job titles and add the requested roles.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.departments ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS name_ar TEXT;
ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS job_level TEXT;
ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TEMP TABLE department_merge_map(source_id UUID PRIMARY KEY,target_id UUID NOT NULL) ON COMMIT DROP;

-- Known naming variants should use the workbook's canonical department names.
INSERT INTO department_merge_map(source_id,target_id)
SELECT source.id,target.id
FROM public.departments source
JOIN LATERAL (
    SELECT id FROM public.departments candidate
    WHERE lower(regexp_replace(btrim(candidate.name),'\s+',' ','g'))='administrative'
    ORDER BY candidate.is_active DESC,candidate.id::text LIMIT 1
) target ON TRUE
WHERE lower(btrim(source.name))='administration' AND source.id<>target.id
ON CONFLICT(source_id) DO NOTHING;

INSERT INTO department_merge_map(source_id,target_id)
SELECT source.id,target.id
FROM public.departments source
JOIN LATERAL (
    SELECT id FROM public.departments candidate
    WHERE lower(regexp_replace(btrim(candidate.name),'\s+',' ','g'))='operations and production'
    ORDER BY candidate.is_active DESC,candidate.id::text LIMIT 1
) target ON TRUE
WHERE lower(regexp_replace(btrim(source.name),'\s+',' ','g')) IN (
    'operation and production','operations & production','operation and productions','operations and productions'
) AND source.id<>target.id
ON CONFLICT(source_id) DO NOTHING;

-- Merge repeated records that differ only by whitespace or letter case.
WITH normalized AS (
    SELECT lower(regexp_replace(btrim(name),'\s+',' ','g')) normalized_name,
           (array_agg(id ORDER BY is_active DESC,id::text))[1] target_id,
           array_agg(id ORDER BY is_active DESC,id::text) ids
    FROM public.departments
    GROUP BY lower(regexp_replace(btrim(name),'\s+',' ','g'))
    HAVING count(*)>1
)
INSERT INTO department_merge_map(source_id,target_id)
SELECT duplicate_id,normalized.target_id
FROM normalized CROSS JOIN LATERAL unnest(normalized.ids) AS duplicates(duplicate_id)
WHERE duplicate_id<>normalized.target_id
ON CONFLICT(source_id) DO NOTHING;

-- Copy each source title to the retained department before archiving duplicates.
INSERT INTO public.job_titles(department_id,name,name_ar,job_level,is_active)
SELECT mapping.target_id,title.name,title.name_ar,title.job_level,title.is_active
FROM department_merge_map mapping
JOIN public.job_titles title ON title.department_id=mapping.source_id
ON CONFLICT(department_id,name) DO UPDATE SET
    name_ar=COALESCE(EXCLUDED.name_ar,public.job_titles.name_ar),
    job_level=COALESCE(EXCLUDED.job_level,public.job_titles.job_level),
    is_active=public.job_titles.is_active OR EXCLUDED.is_active;

UPDATE public.profiles profile SET department_id=mapping.target_id
FROM department_merge_map mapping WHERE profile.department_id=mapping.source_id;

UPDATE public.tasks task SET department=target.name
FROM department_merge_map mapping
JOIN public.departments source ON source.id=mapping.source_id
JOIN public.departments target ON target.id=mapping.target_id
WHERE lower(btrim(COALESCE(task.department,'')))=lower(btrim(source.name));

UPDATE public.departments target SET head_id=source.head_id
FROM department_merge_map mapping
JOIN public.departments source ON source.id=mapping.source_id
WHERE target.id=mapping.target_id AND target.head_id IS NULL AND source.head_id IS NOT NULL;

UPDATE public.job_titles title SET is_active=FALSE
FROM department_merge_map mapping WHERE title.department_id=mapping.source_id;
UPDATE public.departments department SET is_active=FALSE
FROM department_merge_map mapping WHERE department.id=mapping.source_id;
UPDATE public.departments department SET is_active=TRUE
WHERE department.id IN(SELECT target_id FROM department_merge_map);

-- Keep one active row for case/space variants of the same title in a department.
WITH ranked AS (
    SELECT id,department_id,name,
           first_value(id) OVER(PARTITION BY department_id,lower(regexp_replace(btrim(name),'\s+',' ','g')) ORDER BY is_active DESC,id::text) keep_id,
           first_value(name) OVER(PARTITION BY department_id,lower(regexp_replace(btrim(name),'\s+',' ','g')) ORDER BY is_active DESC,id::text) keep_name,
           row_number() OVER(PARTITION BY department_id,lower(regexp_replace(btrim(name),'\s+',' ','g')) ORDER BY is_active DESC,id::text) position
    FROM public.job_titles
), canonical_titles AS (
    SELECT * FROM ranked WHERE position=1
)
UPDATE public.profiles profile SET job_title=canonical.keep_name
FROM canonical_titles canonical
WHERE profile.department_id=canonical.department_id
  AND lower(regexp_replace(btrim(COALESCE(profile.job_title,'')),'\s+',' ','g'))=lower(regexp_replace(btrim(canonical.keep_name),'\s+',' ','g'));

WITH ranked AS (
    SELECT id,row_number() OVER(
        PARTITION BY department_id,lower(regexp_replace(btrim(name),'\s+',' ','g'))
        ORDER BY is_active DESC,id::text
    ) position
    FROM public.job_titles
)
UPDATE public.job_titles title SET is_active=FALSE
FROM ranked WHERE title.id=ranked.id AND ranked.position>1;

WITH requested(department_name,title_name,job_level) AS (VALUES
    ('Operations and Production','Technician','Mid-Level'),
    ('Operations and Production','Barista','Entry-Level'),
    ('Marketing','Marketing Representative','Entry-Level'),
    ('Marketing','Photographer','Mid-Level'),
    ('Sales','Sales Representative','Entry-Level'),
    ('Sales','Customer Services','Entry-Level')
)
INSERT INTO public.job_titles(department_id,name,name_ar,job_level,is_active)
SELECT department.id,requested.title_name,requested.title_name,requested.job_level,TRUE
FROM requested
JOIN public.departments department ON lower(btrim(department.name))=lower(requested.department_name) AND department.is_active=TRUE
ON CONFLICT(department_id,name) DO UPDATE SET job_level=EXCLUDED.job_level,is_active=TRUE;

NOTIFY pgrst,'reload schema';
COMMIT;
