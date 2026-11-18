-- Treat the full System Administrator profile label as an admin for CRM deletion.
-- Keep deletion limited to active privileged profiles and preserve all grants.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_delete_crm_deal(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM false
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'SYSTEM ADMINISTRATOR'
              )
              OR UPPER(COALESCE(profile.job_title, '')) ~ '(^|[^A-Z])(CEO|CHIEF EXECUTIVE|CHIEF EXECUTIVE OFFICER|GM|GENERAL MANAGER|MARKETING MANAGER)([^A-Z]|$)'
              OR COALESCE(to_jsonb(profile)->>'job_title_ar', '') ~ '(الرئيس التنفيذي|المدير العام|مدير[[:space:]]*التسويق)'
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_delete_crm_deal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_delete_crm_deal(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
