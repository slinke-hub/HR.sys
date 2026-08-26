-- Automatic employee IDs displayed by the app as MQ-01, MQ-02, ...
-- The database stores only the numeric sequence in profiles.emp_index.

BEGIN;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS emp_index BIGINT;

CREATE SEQUENCE IF NOT EXISTS public.profiles_emp_index_seq;

ALTER TABLE public.profiles
    ALTER COLUMN emp_index SET DEFAULT nextval('public.profiles_emp_index_seq');

ALTER SEQUENCE public.profiles_emp_index_seq
    OWNED BY public.profiles.emp_index;

-- Preserve every valid existing ID. Assign new values only to missing or
-- duplicated rows so this migration does not renumber existing employees.
WITH ranked AS (
    SELECT id,
           emp_index,
           ROW_NUMBER() OVER (PARTITION BY emp_index ORDER BY created_at NULLS LAST, id) AS duplicate_rank
    FROM public.profiles
), needing_id AS (
    SELECT id,
           ROW_NUMBER() OVER (ORDER BY id) AS offset_value
    FROM ranked
    WHERE emp_index IS NULL OR duplicate_rank > 1
), current_max AS (
    SELECT COALESCE(MAX(emp_index), 0) AS max_value
    FROM public.profiles
)
UPDATE public.profiles AS profile
SET emp_index = current_max.max_value + needing_id.offset_value
FROM needing_id, current_max
WHERE profile.id = needing_id.id;

SELECT setval(
    'public.profiles_emp_index_seq',
    GREATEST(COALESCE((SELECT MAX(emp_index) FROM public.profiles), 0), 1),
    EXISTS (SELECT 1 FROM public.profiles)
);

CREATE UNIQUE INDEX IF NOT EXISTS profiles_emp_index_unique_idx
    ON public.profiles (emp_index);

ALTER TABLE public.profiles
    ALTER COLUMN emp_index SET NOT NULL;

COMMIT;
