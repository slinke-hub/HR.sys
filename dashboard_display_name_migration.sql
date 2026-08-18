-- User-controlled dashboard display name.
-- Keeps the official full_name unchanged for HR records and contracts.

BEGIN;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS display_name VARCHAR(100);

UPDATE public.profiles
SET display_name = NULL
WHERE display_name IS NOT NULL
  AND BTRIM(display_name) = '';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'profiles_display_name_not_blank'
          AND conrelid = 'public.profiles'::regclass
    ) THEN
        ALTER TABLE public.profiles
            ADD CONSTRAINT profiles_display_name_not_blank
            CHECK (display_name IS NULL OR BTRIM(display_name) <> '');
    END IF;
END $$;

UPDATE public.profiles
SET display_name = LEFT(NULLIF(BTRIM(full_name), ''), 100)
WHERE display_name IS NULL
  AND NULLIF(BTRIM(full_name), '') IS NOT NULL;

CREATE OR REPLACE FUNCTION public.protect_profile_privileged_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE caller_role TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;

    SELECT role INTO caller_role
    FROM public.profiles
    WHERE id = auth.uid();

    IF caller_role = 'ADMIN' THEN RETURN NEW; END IF;

    IF (to_jsonb(NEW) - ARRAY['full_name', 'display_name', 'iqama_number', 'phone_number', 'avatar_url', 'last_login', 'birth_date']::TEXT[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['full_name', 'display_name', 'iqama_number', 'phone_number', 'avatar_url', 'last_login', 'birth_date']::TEXT[]) THEN
        RAISE EXCEPTION 'Only an administrator can change protected profile fields'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.protect_profile_privileged_fields() FROM PUBLIC;

DROP TRIGGER IF EXISTS protect_profile_privileged_fields_trigger ON public.profiles;
CREATE TRIGGER protect_profile_privileged_fields_trigger
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_privileged_fields();

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
ON public.profiles FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

COMMENT ON COLUMN public.profiles.display_name IS
    'User-controlled name shown in the dashboard greeting and top bar.';

NOTIFY pgrst, 'reload schema';

COMMIT;
