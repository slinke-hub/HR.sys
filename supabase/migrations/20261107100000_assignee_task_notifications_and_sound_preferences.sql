-- Limit employee task notifications to tasks assigned to that employee and
-- store each user's notification ringtone preference under their own RLS row.
BEGIN;

CREATE TABLE IF NOT EXISTS public.user_notification_preferences (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    sound_enabled boolean NOT NULL DEFAULT true
);

ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_notification_preferences_select_self ON public.user_notification_preferences;
CREATE POLICY user_notification_preferences_select_self
    ON public.user_notification_preferences
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS user_notification_preferences_insert_self ON public.user_notification_preferences;
CREATE POLICY user_notification_preferences_insert_self
    ON public.user_notification_preferences
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS user_notification_preferences_update_self ON public.user_notification_preferences;
CREATE POLICY user_notification_preferences_update_self
    ON public.user_notification_preferences
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

REVOKE ALL ON TABLE public.user_notification_preferences FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.user_notification_preferences TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_employee_task_notification_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    recipient_role text;
    recipient_is_assigned boolean;
BEGIN
    IF NEW.task_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g')))
      INTO recipient_role
      FROM public.profiles AS profile
     WHERE profile.id = NEW.user_id;

    IF recipient_role IS NULL THEN
        RETURN NULL;
    END IF;

    recipient_role := NULLIF(recipient_role, '');
    IF recipient_role IS NULL THEN
        RETURN NULL;
    END IF;

    IF recipient_role <> 'EMPLOYEE' THEN
        RETURN NEW;
    END IF;

    SELECT task_row.assignee_id = NEW.user_id
           OR NEW.user_id = ANY(COALESCE(task_row.assignee_ids, '{}'::uuid[]))
      INTO recipient_is_assigned
      FROM public.tasks AS task_row
     WHERE task_row.id = NEW.task_id;

    IF COALESCE(recipient_is_assigned, false) IS NOT TRUE THEN
        -- Suppress the row (and any outbox work keyed to its returned id) for
        -- employees who are not assigned to this task.
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_employee_task_notification_assignment() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS employee_task_notification_assignment_guard ON public.notifications;
CREATE TRIGGER employee_task_notification_assignment_guard
    BEFORE INSERT ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_employee_task_notification_assignment();

-- Existing task notifications must not remain readable through direct table
-- SELECTs that bypass the filtered notification RPCs.
CREATE POLICY employee_task_notification_assignment_read_guard
    ON public.notifications
    AS RESTRICTIVE
    FOR SELECT TO authenticated
    USING (
        user_id = auth.uid()
        AND (
            task_id IS NULL
            OR EXISTS (
                SELECT 1
                  FROM public.profiles AS viewer
                 WHERE viewer.id = auth.uid()
                   AND NULLIF(UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))), '') IS NOT NULL
                   AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) <> 'EMPLOYEE'
            )
            OR EXISTS (
                SELECT 1
                  FROM public.tasks AS task_row
                 WHERE task_row.id = notifications.task_id
                   AND (
                        task_row.assignee_id = auth.uid()
                        OR auth.uid() = ANY(COALESCE(task_row.assignee_ids, '{}'::uuid[]))
                   )
            )
        )
    );

-- Task email is queued independently of the in-app notification row, so it
-- needs the same assignment boundary even when the notification insert is
-- suppressed.
CREATE OR REPLACE FUNCTION public.enforce_employee_task_email_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    recipient_role text;
    recipient_is_assigned boolean;
BEGIN
    IF NEW.task_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT NULLIF(UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))), '')
      INTO recipient_role
      FROM public.profiles AS profile
     WHERE profile.id = NEW.recipient_id;

    IF recipient_role IS NULL THEN
        RETURN NULL;
    END IF;

    IF recipient_role <> 'EMPLOYEE' THEN
        RETURN NEW;
    END IF;

    SELECT task_row.assignee_id = NEW.recipient_id
           OR NEW.recipient_id = ANY(COALESCE(task_row.assignee_ids, '{}'::uuid[]))
      INTO recipient_is_assigned
      FROM public.tasks AS task_row
     WHERE task_row.id = NEW.task_id;

    IF COALESCE(recipient_is_assigned, false) IS NOT TRUE THEN
        RETURN NULL;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_employee_task_email_assignment() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER employee_task_email_assignment_guard
    BEFORE INSERT ON public.task_email_outbox
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_employee_task_email_assignment();

CREATE OR REPLACE FUNCTION public.list_my_notifications(
    p_limit integer DEFAULT 20,
    p_before timestamptz DEFAULT NULL,
    p_unread_only boolean DEFAULT false
)
RETURNS SETOF public.notifications
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT notification_row.*
      FROM public.notifications AS notification_row
     WHERE notification_row.user_id = auth.uid()
       AND (p_unread_only IS NOT TRUE OR notification_row.is_read IS NOT TRUE)
       AND (p_before IS NULL OR notification_row.created_at < p_before)
       AND (
            EXISTS (
                SELECT 1
                  FROM public.profiles AS viewer
                 WHERE viewer.id = auth.uid()
                   AND NULLIF(UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))), '') IS NOT NULL
                   AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) <> 'EMPLOYEE'
            )
            OR notification_row.task_id IS NULL
            OR EXISTS (
                SELECT 1
                  FROM public.tasks AS task_row
                 WHERE task_row.id = notification_row.task_id
                   AND (
                        task_row.assignee_id = auth.uid()
                        OR auth.uid() = ANY(COALESCE(task_row.assignee_ids, '{}'::uuid[]))
                   )
            )
       )
     ORDER BY notification_row.created_at DESC, notification_row.id DESC
     LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_notification(p_notification_id uuid)
RETURNS SETOF public.notifications
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO public, pg_temp
AS $$
    SELECT notification_row.*
      FROM public.notifications AS notification_row
     WHERE notification_row.id = p_notification_id
       AND notification_row.user_id = auth.uid()
       AND (
            EXISTS (
                SELECT 1
                  FROM public.profiles AS viewer
                 WHERE viewer.id = auth.uid()
                   AND NULLIF(UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))), '') IS NOT NULL
                   AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) <> 'EMPLOYEE'
            )
            OR notification_row.task_id IS NULL
            OR EXISTS (
                SELECT 1
                  FROM public.tasks AS task_row
                 WHERE task_row.id = notification_row.task_id
                   AND (
                        task_row.assignee_id = auth.uid()
                        OR auth.uid() = ANY(COALESCE(task_row.assignee_ids, '{}'::uuid[]))
                   )
            )
       );
$$;

CREATE OR REPLACE FUNCTION public.get_my_unread_notification_count()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO public, pg_temp
AS $$
    SELECT count(*)::bigint
      FROM public.notifications AS notification_row
     WHERE notification_row.user_id = auth.uid()
       AND notification_row.is_read IS NOT TRUE
       AND (
            EXISTS (
                SELECT 1
                  FROM public.profiles AS viewer
                 WHERE viewer.id = auth.uid()
                   AND NULLIF(UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))), '') IS NOT NULL
                   AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) <> 'EMPLOYEE'
            )
            OR notification_row.task_id IS NULL
            OR EXISTS (
                SELECT 1
                  FROM public.tasks AS task_row
                 WHERE task_row.id = notification_row.task_id
                   AND (
                        task_row.assignee_id = auth.uid()
                        OR auth.uid() = ANY(COALESCE(task_row.assignee_ids, '{}'::uuid[]))
                   )
            )
       );
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
