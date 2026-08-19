-- ========================================================
-- HARD DELETE ALL EMPLOYEES (KEEPING ADMINS)
-- ========================================================
-- This script completely removes all non-admin employees from both 
-- the 'profiles' table and the Supabase authentication system ('auth.users').
-- It clears any dependent data in tables like notifications, tasks, etc., to avoid foreign key constraints.

DO $$
DECLARE
    rec RECORD;
BEGIN
    -- 0. Remove department heads that are about to be deleted
    UPDATE public.departments 
    SET head_id = NULL 
    WHERE head_id IN (SELECT id FROM public.profiles WHERE role != 'ADMIN');

    -- 1. Delete dependent data first to satisfy foreign key constraints
    -- We delete any record associated with a user who is NOT an ADMIN
    DELETE FROM public.notifications 
    WHERE user_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));
    
    DELETE FROM public.payroll 
    WHERE employee_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));
    
    DELETE FROM public.performance_goals 
    WHERE employee_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));
    
    -- Tasks could be referencing as assignee or creator
    DELETE FROM public.tasks 
    WHERE assignee_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'))
       OR created_by IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));

    DELETE FROM public.leave_requests 
    WHERE employee_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));

    DELETE FROM public.document_requests 
    WHERE employee_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));

    DELETE FROM public.employee_documents 
    WHERE employee_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));

    DELETE FROM public.expenses 
    WHERE employee_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));

    DELETE FROM public.time_punches 
    WHERE employee_id IN (SELECT id FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles WHERE role = 'ADMIN'));

    -- 2. Delete all non-admin profiles (this clears unique constraints like Iqama)
    DELETE FROM public.profiles WHERE role != 'ADMIN';
    
    -- 3. Delete all authentication accounts that no longer have a profile
    FOR rec IN 
        SELECT id FROM auth.users 
        WHERE id NOT IN (SELECT id FROM public.profiles)
    LOOP
        DELETE FROM auth.users WHERE id = rec.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
