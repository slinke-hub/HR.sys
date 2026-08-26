-- Allow system administrators to add department-specific job titles safely.
BEGIN;

CREATE TABLE IF NOT EXISTS public.job_titles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(department_id, name)
);

ALTER TABLE public.job_titles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS job_titles_authenticated_select ON public.job_titles;
CREATE POLICY job_titles_authenticated_select ON public.job_titles
FOR SELECT TO authenticated USING (is_active = TRUE);

CREATE OR REPLACE FUNCTION public.admin_add_department_job_title(p_department_id UUID, p_name TEXT)
RETURNS public.job_titles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    clean_name TEXT := NULLIF(BTRIM(COALESCE(p_name, '')), '');
    existing_title public.job_titles%ROWTYPE;
    saved_title public.job_titles%ROWTYPE;
BEGIN
    IF NOT public.is_system_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only an administrator can add department job titles' USING ERRCODE = '42501';
    END IF;
    IF clean_name IS NULL THEN RAISE EXCEPTION 'Job title is required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id = p_department_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Select an active department';
    END IF;

    SELECT * INTO existing_title
    FROM public.job_titles
    WHERE department_id = p_department_id AND LOWER(name) = LOWER(clean_name)
    ORDER BY created_at
    LIMIT 1;

    IF FOUND THEN
        UPDATE public.job_titles SET name = clean_name, is_active = TRUE
        WHERE id = existing_title.id RETURNING * INTO saved_title;
    ELSE
        INSERT INTO public.job_titles(department_id, name, is_active)
        VALUES (p_department_id, clean_name, TRUE)
        RETURNING * INTO saved_title;
    END IF;
    RETURN saved_title;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_add_department_job_title(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_add_department_job_title(UUID, TEXT) TO authenticated;
GRANT SELECT ON public.job_titles TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
