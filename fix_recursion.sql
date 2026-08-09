-- Fix Infinite Recursion on Profiles Table

-- 1. Create a SECURITY DEFINER function to securely get the current user's role
--    This function bypasses RLS, so it won't trigger an infinite loop when called from a policy!
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text AS $$
DECLARE
  user_role text;
BEGIN
  SELECT role INTO user_role FROM public.profiles WHERE id = auth.uid();
  RETURN user_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Drop the recursive policy on profiles
DROP POLICY IF EXISTS "Admins can read all profiles" ON profiles;

-- 3. Recreate the policy using the secure function to avoid infinite recursion
CREATE POLICY "Admins can read all profiles" ON profiles 
FOR SELECT USING (
    public.get_user_role() = 'ADMIN'
);

-- Note: Policies on OTHER tables (like attendance, etc.) that do `SELECT 1 FROM profiles` 
-- will now work correctly without looping, because when they query `profiles`, the `profiles` 
-- policy uses `get_user_role()`, which bypasses RLS and ends the chain.
