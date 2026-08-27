-- Archive departments safely instead of deleting referenced organizational history.
BEGIN;

CREATE OR REPLACE FUNCTION public.archive_department(p_department_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id=auth.uid()
          AND upper(COALESCE(profile.role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
    ) THEN
        RAISE EXCEPTION 'Only administrators can archive departments';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id=p_department_id) THEN
        RAISE EXCEPTION 'Department not found';
    END IF;

    UPDATE public.job_titles SET is_active=FALSE WHERE department_id=p_department_id;
    UPDATE public.departments SET is_active=FALSE WHERE id=p_department_id;
    RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.archive_department(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_department(UUID) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
