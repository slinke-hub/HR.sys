BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.list_accessible_project_profiles()') IS NULL THEN
        RAISE EXCEPTION 'Required function public.list_accessible_project_profiles() is missing';
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.list_accessible_project_profiles() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_accessible_project_profiles() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
