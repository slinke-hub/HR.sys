-- Assign the Employee Directory IDs in the requested order.
-- The UI renders these numeric values as MQ-01, MQ-02, etc.
BEGIN;

CREATE TEMP TABLE requested_employee_ids (
  full_name text PRIMARY KEY,
  employee_number bigint NOT NULL
) ON COMMIT DROP;

INSERT INTO requested_employee_ids (full_name, employee_number) VALUES
  ('Mohamed Zeyad', 1),
  ('Abdullah Zeyad', 2),
  ('Hussain Ahmed Bhhari', 3),
  ('Hassan Hussain Rasmi', 4),
  ('Jamal Yousuf', 5),
  ('Montasir Eltayeb', 6),
  ('Ghassan Ahmed Bhhari', 7),
  ('InesMadani', 8),
  ('Mohamed Afefi', 9),
  ('Arif Almiri', 10),
  ('Mohamed Omer', 11),
  ('Boshra Simsim eya', 12),
  ('Awah', 13),
  ('Aseil Maqbali', 14),
  ('Bilal Gholam', 15),
  ('Ravaan Baheis', 16),
  ('Adel Al-Qardhi', 17),
  ('Abdulfattah Karawan', 18),
  ('Abdulhadi Ahmed', 19),
  ('Omar Al-Saidi', 20),
  ('Uml Ibrahim', 21),
  ('Hanouf Omer', 22),
  ('Ibrahim Saeed', 23);

-- Move matched rows out of the way first so the unique index cannot collide
-- with an existing employee number during the reassignment.
UPDATE public.profiles profile
SET emp_index = 1000000 + profile.emp_index
WHERE lower(trim(profile.full_name)) IN (
  SELECT lower(trim(full_name)) FROM requested_employee_ids
);

UPDATE public.profiles profile
SET emp_index = requested.employee_number
FROM requested_employee_ids requested
WHERE lower(trim(profile.full_name)) = lower(trim(requested.full_name));

SELECT setval(
  'public.profiles_emp_index_seq',
  GREATEST(COALESCE((SELECT MAX(emp_index) FROM public.profiles), 1), 1),
  true
);

COMMIT;
