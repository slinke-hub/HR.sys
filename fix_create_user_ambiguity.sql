-- Drop all conflicting versions of create_user_by_admin
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.create_user_by_admin(TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.create_user_by_admin();

-- The correct one has (TEXT, TEXT, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, TEXT)
-- We will keep this one, but just in case, we can also recreate it to ensure it's the only one left.
