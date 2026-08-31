-- Assign the next employee number automatically when a profile is created.
-- The application displays emp_index 51 as MQ-51.
BEGIN;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS emp_index BIGINT;

CREATE SEQUENCE IF NOT EXISTS public.profiles_emp_index_seq;

ALTER SEQUENCE public.profiles_emp_index_seq
    OWNED BY public.profiles.emp_index;

SELECT setval(
    'public.profiles_emp_index_seq',
    GREATEST(COALESCE((SELECT MAX(emp_index) FROM public.profiles), 0), 1),
    EXISTS (SELECT 1 FROM public.profiles WHERE emp_index IS NOT NULL)
);

ALTER TABLE public.profiles
    ALTER COLUMN emp_index SET DEFAULT nextval('public.profiles_emp_index_seq');

CREATE OR REPLACE FUNCTION public.assign_profile_employee_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    sequence_value BIGINT;
BEGIN
    -- Serialize automatic and explicitly imported employee numbers so the
    -- sequence never falls behind an imported value.
    PERFORM pg_advisory_xact_lock(hashtext('profiles_emp_index_assignment'));

    IF NEW.emp_index IS NULL THEN
        NEW.emp_index := nextval('public.profiles_emp_index_seq');
    ELSE
        SELECT last_value INTO sequence_value FROM public.profiles_emp_index_seq;
        IF NEW.emp_index > sequence_value THEN
            PERFORM setval('public.profiles_emp_index_seq', NEW.emp_index, TRUE);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_assign_employee_number ON public.profiles;
CREATE TRIGGER profiles_assign_employee_number
BEFORE INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.assign_profile_employee_number();

CREATE UNIQUE INDEX IF NOT EXISTS profiles_emp_index_unique_idx
    ON public.profiles(emp_index);

NOTIFY pgrst, 'reload schema';
COMMIT;
