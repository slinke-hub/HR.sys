-- ========================================================
-- FUNCTION TO TRULY DELETE ALL EMPLOYEES (EXCEPT ADMINS)
-- ========================================================
-- This function deletes users from auth.users (which cascades to profiles)
-- It will NOT delete users who have the 'ADMIN' role in the profiles table.

CREATE OR REPLACE FUNCTION delete_all_employees()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    user_rec RECORD;
BEGIN
    -- Check if the caller is an Admin
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can delete employees';
    END IF;

    -- Loop through all users who are NOT admins
    FOR user_rec IN 
        SELECT u.id 
        FROM auth.users u
        JOIN public.profiles p ON p.id = u.id
        WHERE p.role != 'ADMIN'
    LOOP
        -- Delete from auth.users (this cascades to profiles and other linked tables if constraints are set up, 
        -- but just to be safe we can delete from profiles first if needed. 
        -- However, auth.users -> profiles usually has ON DELETE CASCADE.
        
        DELETE FROM public.profiles WHERE id = user_rec.id;
        DELETE FROM auth.users WHERE id = user_rec.id;
    END LOOP;
END;
$$;
