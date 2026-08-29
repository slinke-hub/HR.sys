DO $$
DECLARE
    v_admin_id UUID;
    v_role VARCHAR;
    v_is_active BOOLEAN;
    v_job_title VARCHAR;
    v_new_user_id UUID;
BEGIN
    -- 1. Find the admin user ID
    SELECT id INTO v_admin_id FROM auth.users WHERE email = 'privatepple@gmail.com' LIMIT 1;
    
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Admin user not found!';
    END IF;

    -- 2. Check profile fields
    SELECT role, is_active, job_title INTO v_role, v_is_active, v_job_title
    FROM public.profiles WHERE id = v_admin_id;

    RAISE NOTICE 'Profile Check -> Role: %, IsActive: %, JobTitle: %', v_role, v_is_active, v_job_title;

    -- 3. Simulate being logged in as the admin
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', v_admin_id), true);
    
    -- 4. Try to create a dummy user
    BEGIN
        v_new_user_id := public.create_user_by_admin(
            'test_creation_debug@example.com',
            'Password123!',
            'EMPLOYEE',
            'Tester',
            'Test User',
            '1234567890',
            '123456789',
            'EMP0002'
        );
        RAISE NOTICE 'Success! Created user with ID: %', v_new_user_id;
        
        -- Rollback the creation so we don't clutter the DB
        RAISE EXCEPTION 'Debug complete, rolling back.';
    EXCEPTION 
        WHEN OTHERS THEN
            IF SQLERRM = 'Debug complete, rolling back.' THEN
                RAISE NOTICE 'Test passed successfully.';
            ELSE
                RAISE NOTICE 'Error creating user: % %', SQLSTATE, SQLERRM;
            END IF;
    END;
END $$;
