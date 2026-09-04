-- Allow administrators to see the complete user directory, including locked
-- accounts.  Existing profile policies can remain in place; this permissive
-- policy adds the admin capability without changing access for other roles.

CREATE OR REPLACE FUNCTION public.admin_can_read_all_profiles()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND UPPER(COALESCE(role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
  );
$$;

REVOKE ALL ON FUNCTION public.admin_can_read_all_profiles() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_can_read_all_profiles() TO authenticated;

DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
CREATE POLICY "Admins can view all profiles"
ON public.profiles
FOR SELECT
TO authenticated
USING (public.admin_can_read_all_profiles());
