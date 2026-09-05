-- Assign Employee Directory IDs in the requested order.
-- The UI renders these numeric values as MQ-01, MQ-02, etc.
BEGIN;

LOCK TABLE public.profiles IN EXCLUSIVE MODE;

CREATE TEMP TABLE requested_employee_ids (
  employee_number bigint PRIMARY KEY,
  full_name text UNIQUE NOT NULL
) ON COMMIT DROP;

INSERT INTO requested_employee_ids (employee_number, full_name) VALUES
  (1,  'Mohamed Hassan Abkar'),
  (2,  'Abdullah Hassan Abkar'),
  (3,  'Hussain Ahmed Bhhari'),
  (4,  'Hassan Hussain Hassan'),
  (5,  'Jamal Yousuf'),
  (6,  'Montasir Jafar Ahmed Eltayeb'),
  (7,  'Ghassan Ahmed Bhhari'),
  (8,  'InesMadani'),
  (9,  'Mohamed Afefi'),
  (10, 'Arif Almiri'),
  (11, 'Mohamed Omer'),
  (12, 'Aseil Muneer Saeed'),
  (13, 'Bilal Ahmad Ghous'),
  (14, 'Adel Saad Abdullah Alqardhi'),
  (15, 'Abdulhadi Ahmed'),
  (16, 'Omar Mohamed Makhimer'),
  (17, 'Hanouf Omer'),
  (18, 'Ibrahim Saeed'),
  (19, 'Um Ibrahim'),
  (20, 'Boshra Mohamed Simsim eya'),
  (21, 'Arwah'),
  (22, 'Rayaan Baheis'),
  (23, 'Abdulfatah Mohamed Karawan'),
  (24, 'Abdullah Alselme');

CREATE TEMP TABLE requested_profile_ids ON COMMIT DROP AS
SELECT requested.employee_number, requested.full_name, profile.id
FROM requested_employee_ids requested
JOIN public.profiles profile
  ON regexp_replace(lower(btrim(profile.full_name)), '\s+', '', 'g') =
     regexp_replace(lower(btrim(requested.full_name)), '\s+', '', 'g');

DO $$
DECLARE
  missing_names text;
  duplicate_names text;
BEGIN
  SELECT string_agg(requested.full_name, ', ' ORDER BY requested.employee_number)
  INTO missing_names
  FROM requested_employee_ids requested
  LEFT JOIN requested_profile_ids matched USING (employee_number)
  WHERE matched.id IS NULL;

  SELECT string_agg(matches.full_name, ', ' ORDER BY matches.employee_number)
  INTO duplicate_names
  FROM (
    SELECT employee_number, min(full_name) AS full_name
    FROM requested_profile_ids
    GROUP BY employee_number
    HAVING count(*) > 1
  ) matches;

  IF missing_names IS NOT NULL THEN
    RAISE EXCEPTION 'Employee ID reassignment stopped. Profiles not found: %', missing_names;
  END IF;
  IF duplicate_names IS NOT NULL THEN
    RAISE EXCEPTION 'Employee ID reassignment stopped. Duplicate profile names: %', duplicate_names;
  END IF;
END
$$;

-- Relocate every current value first so the unique employee-number index cannot
-- collide while IDs are reordered.
WITH relocation AS (
  SELECT id, row_number() OVER (ORDER BY emp_index NULLS LAST, id) AS position
  FROM public.profiles
), offset_value AS (
  SELECT GREATEST(COALESCE(max(abs(emp_index)), 0), 1000000) + 1000 AS value
  FROM public.profiles
)
UPDATE public.profiles profile
SET emp_index = offset_value.value + relocation.position
FROM relocation, offset_value
WHERE profile.id = relocation.id;

UPDATE public.profiles profile
SET emp_index = matched.employee_number
FROM requested_profile_ids matched
WHERE profile.id = matched.id;

-- Any profile outside the supplied list remains valid and receives the next
-- available ID after MQ-24, preserving its previous relative order.
WITH remaining AS (
  SELECT profile.id, row_number() OVER (ORDER BY profile.emp_index, profile.id) AS position
  FROM public.profiles profile
  WHERE NOT EXISTS (
    SELECT 1 FROM requested_profile_ids matched WHERE matched.id = profile.id
  )
)
UPDATE public.profiles profile
SET emp_index = 24 + remaining.position
FROM remaining
WHERE profile.id = remaining.id;

SELECT setval(
  'public.profiles_emp_index_seq',
  GREATEST(COALESCE((SELECT max(emp_index) FROM public.profiles), 1), 1),
  true
);

COMMIT;
