-- Enforce the existing Pages Access Controls grant for Schedule & Reminders.
-- Existing permission rows and reminders are intentionally left unchanged.
BEGIN;

CREATE OR REPLACE FUNCTION public.has_effective_page_access_internal(
    p_user_id uuid,
    p_page text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE
    normalized_page text := NULLIF(BTRIM(p_page), '');
    profile_role text;
    profile_job_title text;
    profile_job_title_ar text;
    profile_department_id uuid;
    has_individual_access boolean := false;
    has_role_access boolean := false;
    has_department_access boolean := false;
BEGIN
    IF p_user_id IS NULL OR normalized_page IS NULL THEN
        RETURN false;
    END IF;

    SELECT
        profile.role,
        profile.job_title,
        COALESCE(to_jsonb(profile)->>'job_title_ar', ''),
        profile.department_id
    INTO
        profile_role,
        profile_job_title,
        profile_job_title_ar,
        profile_department_id
    FROM public.profiles AS profile
    WHERE profile.id = p_user_id
      AND profile.is_active IS DISTINCT FROM false;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    IF (
        UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile_role, ''), '[_-]+', ' ', 'g'))) IN (
            'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'
        )
        OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile_job_title, ''), '[_-]+', ' ', 'g'))) IN (
            'GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
        )
        OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile_job_title, ''), '[_-]+', ' ', 'g'))) ~
            '^(GENERAL MANAGER|CHIEF EXECUTIVE OFFICER) \((GM|CEO)\)$'
        OR profile_job_title_ar IN ('المدير العام', 'الرئيس التنفيذي')
    ) THEN
        RETURN true;
    END IF;

    -- Load every applicable grant source independently. Any source failure
    -- reaches the exception handler and denies the request, even if a later
    -- source would otherwise contain a grant.
    SELECT EXISTS (
        SELECT 1
        FROM public.user_permissions AS individual_permission
        WHERE individual_permission.user_id = p_user_id
          AND individual_permission.allowed_pages ? normalized_page
    ) INTO has_individual_access;

    SELECT EXISTS (
        SELECT 1
        FROM public.role_permissions AS role_permission
        WHERE role_permission.role = UPPER(BTRIM(COALESCE(profile_role, '')))
          AND role_permission.allowed_pages ? normalized_page
    ) INTO has_role_access;

    IF profile_department_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.role_permissions AS department_permission
            WHERE department_permission.role = 'DEPT_' || profile_department_id::text
              AND department_permission.allowed_pages ? normalized_page
        ) INTO has_department_access;
    END IF;

    RETURN COALESCE(has_individual_access, false)
        OR COALESCE(has_role_access, false)
        OR COALESCE(has_department_access, false);
EXCEPTION WHEN OTHERS THEN
    -- Authorization must fail closed if any authoritative source cannot be read.
    RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.has_effective_page_access_internal(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_effective_page_access_internal(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.has_my_page_access(p_page text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;
    RETURN COALESCE(public.has_effective_page_access_internal(auth.uid(), p_page), false);
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.has_my_page_access(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_my_page_access(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_due_schedule_reminders_for_dispatch(p_limit integer DEFAULT 100)
RETURNS SETOF public.reminders
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
    SELECT reminder.*
    FROM public.reminders AS reminder
    WHERE reminder.status = 'pending'
      AND reminder.due_date <= now()
      AND reminder.last_notified_at IS NULL
      AND public.has_effective_page_access_internal(reminder.user_id, 'schedule')
    ORDER BY reminder.due_date, reminder.id
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
$$;

REVOKE ALL ON FUNCTION public.list_due_schedule_reminders_for_dispatch(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_due_schedule_reminders_for_dispatch(integer) TO service_role;

DROP POLICY IF EXISTS "Users can view their reminders" ON public.reminders;
CREATE POLICY "Users can view their reminders"
    ON public.reminders FOR SELECT TO authenticated
    USING (
        user_id = auth.uid()
        AND public.has_my_page_access('schedule')
    );

DROP POLICY IF EXISTS "Users can create their reminders" ON public.reminders;
CREATE POLICY "Users can create their reminders"
    ON public.reminders FOR INSERT TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        AND public.has_my_page_access('schedule')
    );

DROP POLICY IF EXISTS "Users can update their reminders" ON public.reminders;
CREATE POLICY "Users can update their reminders"
    ON public.reminders FOR UPDATE TO authenticated
    USING (
        user_id = auth.uid()
        AND public.has_my_page_access('schedule')
    )
    WITH CHECK (
        user_id = auth.uid()
        AND public.has_my_page_access('schedule')
    );

DROP POLICY IF EXISTS "Users can delete their reminders" ON public.reminders;
CREATE POLICY "Users can delete their reminders"
    ON public.reminders FOR DELETE TO authenticated
    USING (
        user_id = auth.uid()
        AND public.has_my_page_access('schedule')
    );

COMMENT ON FUNCTION public.has_my_page_access(text) IS
    'Returns the current authenticated employee effective Pages Access Controls decision.';
COMMENT ON FUNCTION public.has_effective_page_access_internal(uuid, text) IS
    'Service-role-only evaluator for trusted backend authorization paths.';
COMMENT ON FUNCTION public.list_due_schedule_reminders_for_dispatch(integer) IS
    'Service-role-only due reminder list filtered by effective Schedule access.';

COMMIT;
