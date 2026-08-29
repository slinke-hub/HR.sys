-- 1. Ensure the user is an ADMIN and is ACTIVE
UPDATE public.profiles
SET role = 'ADMIN',
    is_active = true
WHERE id = (
    SELECT id FROM auth.users WHERE email = 'privatepple@gmail.com' LIMIT 1
);

-- 2. Ensure the authenticated role has permission to execute the function
GRANT EXECUTE ON FUNCTION public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT) TO authenticated;
