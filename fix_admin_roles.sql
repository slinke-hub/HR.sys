-- FIX FOR ADMIN UPDATING ROLES
-- This grants ADMIN users the permission to update any profile, enabling the role change feature.
-- Users may update their own row for profile/avatar features, while the trigger
-- below prevents them from changing role or any other protected field.

DROP POLICY IF EXISTS "Admins can update all profiles" ON profiles;
CREATE POLICY "Admins can update all profiles" ON profiles FOR UPDATE USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
CREATE POLICY "Users can update their own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

CREATE OR REPLACE FUNCTION public.protect_profile_privileged_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    caller_role TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;

    SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
    IF caller_role = 'ADMIN' THEN RETURN NEW; END IF;

    IF (to_jsonb(NEW) - ARRAY['full_name', 'iqama_number', 'phone_number', 'avatar_url', 'last_login', 'birth_date']::TEXT[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['full_name', 'iqama_number', 'phone_number', 'avatar_url', 'last_login', 'birth_date']::TEXT[]) THEN
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
FOR EACH ROW
EXECUTE FUNCTION public.protect_profile_privileged_fields();
