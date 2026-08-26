-- Atomically persist UI, department, employee-name, and job-title translations.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_save_translation_bundle(
    p_ui_translations JSONB DEFAULT '[]'::JSONB,
    p_department_translations JSONB DEFAULT '[]'::JSONB,
    p_profile_translations JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    item JSONB;
    ui_count INTEGER := 0;
    department_count INTEGER := 0;
    profile_count INTEGER := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN'
    ) THEN
        RAISE EXCEPTION 'Only an administrator can save system translations' USING ERRCODE = '42501';
    END IF;

    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(p_ui_translations, '[]'::JSONB)) LOOP
        IF NULLIF(BTRIM(item->>'trans_key'), '') IS NULL THEN
            RAISE EXCEPTION 'Translation key cannot be empty' USING ERRCODE = '22023';
        END IF;
        INSERT INTO public.system_translations (trans_key, trans_en, trans_ar, updated_at)
        VALUES (item->>'trans_key', COALESCE(item->>'trans_en', ''), COALESCE(item->>'trans_ar', ''), NOW())
        ON CONFLICT (trans_key) DO UPDATE
        SET trans_en = EXCLUDED.trans_en,
            trans_ar = EXCLUDED.trans_ar,
            updated_at = NOW();
        ui_count := ui_count + 1;
    END LOOP;

    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(p_department_translations, '[]'::JSONB)) LOOP
        UPDATE public.departments
        SET name_ar = NULLIF(BTRIM(item->>'name_ar'), '')
        WHERE id = (item->>'department_id')::UUID;
        IF FOUND THEN department_count := department_count + 1; END IF;
    END LOOP;

    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(p_profile_translations, '[]'::JSONB)) LOOP
        UPDATE public.profiles
        SET display_name_ar = NULLIF(BTRIM(item->>'display_name_ar'), ''),
            job_title_ar = NULLIF(BTRIM(item->>'job_title_ar'), '')
        WHERE id = (item->>'profile_id')::UUID;
        IF FOUND THEN profile_count := profile_count + 1; END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'ui_translations_saved', ui_count,
        'departments_saved', department_count,
        'profiles_saved', profile_count
    );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_save_translation_bundle(JSONB, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_save_translation_bundle(JSONB, JSONB, JSONB) TO authenticated;

COMMIT;
