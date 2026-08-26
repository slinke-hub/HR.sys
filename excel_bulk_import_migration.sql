-- Database support for Excel employee imports.
-- Safe to run repeatedly; existing employee records are preserved.
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS hire_date DATE;

COMMENT ON COLUMN public.profiles.hire_date IS
'Employee hire date imported from the MUQAM HR Excel employee template.';
