-- Durable admin edits for the user directory and job-title translations.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.job_titles ADD COLUMN IF NOT EXISTS name_ar TEXT;

CREATE OR REPLACE FUNCTION public.save_user_directory_changes(p_changes JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE
    item JSONB;
    saved_count INTEGER := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id=auth.uid()
          AND upper(COALESCE(profile.role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
    ) THEN
        RAISE EXCEPTION 'Only administrators can save the user directory' USING ERRCODE='42501';
    END IF;

    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(p_changes,'[]'::JSONB)) LOOP
        IF NULLIF(item->>'id','') IS NULL THEN RAISE EXCEPTION 'User id is required'; END IF;
        UPDATE public.profiles
        SET department_id=NULLIF(item->>'department_id','')::UUID,
            job_title=COALESCE(item->>'job_title',''),
            role=COALESCE(NULLIF(item->>'role',''),role),
            manager_id=NULLIF(item->>'manager_id','')::UUID
        WHERE id=(item->>'id')::UUID;
        IF FOUND THEN saved_count:=saved_count+1; END IF;
    END LOOP;
    RETURN jsonb_build_object('updated_count',saved_count);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_job_title_translation(p_job_title_id UUID,p_name_ar TEXT)
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
        RAISE EXCEPTION 'Only administrators can edit job-title translations' USING ERRCODE='42501';
    END IF;
    UPDATE public.job_titles SET name_ar=NULLIF(btrim(p_name_ar),'') WHERE id=p_job_title_id;
    RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.save_user_directory_changes(JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_job_title_translation(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_user_directory_changes(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_job_title_translation(UUID,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
