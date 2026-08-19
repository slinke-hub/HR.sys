-- ========================================================
-- CLEANUP SCRIPT: DELETE ORPHANED USERS
-- ========================================================
-- If you truncated the 'profiles' table, the actual user accounts in 'auth.users' 
-- were not deleted. This causes a 409 Conflict when you try to recreate them with the same email.
-- Run this script in your Supabase SQL Editor to delete any users from 'auth.users' 
-- that no longer have a profile.

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN 
        SELECT id FROM auth.users 
        WHERE id NOT IN (SELECT id FROM public.profiles)
    LOOP
        DELETE FROM auth.users WHERE id = rec.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
