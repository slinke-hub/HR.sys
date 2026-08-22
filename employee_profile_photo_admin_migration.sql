-- Allow active Admin and HR Manager users to save employee profile photos.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.can_manage_employee_photos(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_user_id
          AND is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(COALESCE(role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN')
              OR UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_manage_employee_photos(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_employee_photos(UUID) TO authenticated;

DROP POLICY IF EXISTS "Admin and HR can update employee profile photos" ON public.profiles;
CREATE POLICY "Admin and HR can update employee profile photos"
ON public.profiles
FOR UPDATE
TO authenticated
USING (public.can_manage_employee_photos(auth.uid()))
WITH CHECK (public.can_manage_employee_photos(auth.uid()));
