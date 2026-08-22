-- Permit each authenticated employee to persist their own profile photo.
-- This makes profile photos available to shared views such as Team Hierarchy.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Employees can update their own profile photo" ON public.profiles;
CREATE POLICY "Employees can update their own profile photo"
ON public.profiles
FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());
