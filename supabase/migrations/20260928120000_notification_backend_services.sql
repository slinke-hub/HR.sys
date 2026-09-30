-- Authoritative notification/device services for Web and future native clients.
-- All caller identity is derived from auth.uid(); clients cannot supply a user id.
BEGIN;

ALTER TABLE public.push_subscriptions
  ADD COLUMN IF NOT EXISTS platform text NOT NULL DEFAULT 'web',
  ADD COLUMN IF NOT EXISTS push_token text,
  ADD COLUMN IF NOT EXISTS device_name text,
  ADD COLUMN IF NOT EXISTS app_version text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.push_subscriptions'::regclass
      AND conname = 'push_subscriptions_platform_check'
  ) THEN
    ALTER TABLE public.push_subscriptions
      ADD CONSTRAINT push_subscriptions_platform_check
      CHECK (platform IN ('web', 'ios', 'android'));
  END IF;
END $$;

DROP POLICY IF EXISTS "Users can manage their own notifications" ON public.notifications;
CREATE POLICY "Users can read their own notifications"
  ON public.notifications FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users manage their push subscriptions" ON public.push_subscriptions;
CREATE POLICY "Users can read their own push subscriptions"
  ON public.push_subscriptions FOR SELECT TO authenticated
  USING (user_id = auth.uid());

REVOKE INSERT, UPDATE, DELETE ON public.notifications FROM authenticated;
GRANT SELECT ON public.notifications TO authenticated;
REVOKE INSERT, UPDATE, DELETE, SELECT ON public.push_subscriptions FROM authenticated;

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
  SELECT n.*
  FROM public.notifications n
  WHERE n.user_id = auth.uid()
    AND (p_unread_only IS NOT TRUE OR n.is_read IS NOT TRUE)
    AND (p_before IS NULL OR n.created_at < p_before)
  ORDER BY n.created_at DESC, n.id DESC
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
  SELECT n.*
  FROM public.notifications n
  WHERE n.id = p_notification_id AND n.user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_my_unread_notification_count()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO public, pg_temp
AS $$
  SELECT count(*)::bigint
  FROM public.notifications
  WHERE user_id = auth.uid() AND is_read IS NOT TRUE;
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE changed integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notifications
     SET is_read = true, read_at = COALESCE(read_at, now())
   WHERE id = p_notification_id AND user_id = auth.uid();
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed = 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE changed integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  UPDATE public.notifications
     SET is_read = true, read_at = COALESCE(read_at, now())
   WHERE user_id = auth.uid() AND is_read IS NOT TRUE;
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_my_notification(p_notification_id uuid)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE changed integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.notifications
   WHERE id = p_notification_id AND user_id = auth.uid();
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed = 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_notification_secure(
  p_recipient_id uuid,
  p_message text,
  p_task_id uuid DEFAULT NULL
)
RETURNS public.notifications
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE
  caller_id uuid := auth.uid();
  caller_role text;
  task_row public.tasks%ROWTYPE;
  notification_row public.notifications%ROWTYPE;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_recipient_id IS NULL OR NULLIF(BTRIM(p_message), '') IS NULL THEN
    RAISE EXCEPTION 'Recipient and message are required' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_recipient_id) THEN
    RAISE EXCEPTION 'Recipient does not exist' USING ERRCODE = '22023';
  END IF;

  SELECT UPPER(REPLACE(COALESCE(role, ''), '_', ' ')) INTO caller_role
  FROM public.profiles WHERE id = caller_id AND is_active IS TRUE;

  IF p_task_id IS NOT NULL THEN
    SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id;
    IF NOT FOUND OR NOT public.can_access_task(p_task_id, caller_id) THEN
      RAISE EXCEPTION 'Task notification is not authorized' USING ERRCODE = '42501';
    END IF;
    IF p_recipient_id <> task_row.created_by
       AND p_recipient_id <> task_row.assignee_id
       AND NOT (p_recipient_id = ANY(COALESCE(task_row.assignee_ids, '{}'::uuid[])))
       AND p_recipient_id <> task_row.supervisor_id
       AND NOT (p_recipient_id = ANY(COALESCE(task_row.watchers, '{}'::uuid[])))
       AND NOT (p_recipient_id = ANY(COALESCE(task_row.visible_to, '{}'::uuid[]))) THEN
      RAISE EXCEPTION 'Recipient is not related to the task' USING ERRCODE = '42501';
    END IF;
  ELSIF p_recipient_id <> caller_id
     AND caller_role NOT IN ('ADMIN', 'MANAGER', 'SUPERVISOR', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN') THEN
    RAISE EXCEPTION 'Only an authorized manager may notify another user' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
  VALUES (
    p_recipient_id,
    LEFT(BTRIM(p_message), 2000),
    CASE WHEN p_task_id IS NULL THEN 'user_notification' ELSE 'task_assigned' END,
    p_task_id,
    caller_id,
    CASE WHEN p_task_id IS NULL THEN NULL ELSE '/?view=tasks&task=' || p_task_id END,
    CASE WHEN p_task_id IS NULL
      THEN '{}'::jsonb
      ELSE jsonb_build_object('target_type', 'TASK', 'target_id', p_task_id, 'task_title', task_row.title, 'actor_id', caller_id)
    END
  )
  RETURNING * INTO notification_row;
  RETURN notification_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_notification_device(
  p_platform text,
  p_push_token text DEFAULT NULL,
  p_endpoint text DEFAULT NULL,
  p_p256dh text DEFAULT NULL,
  p_auth_key text DEFAULT NULL,
  p_device_name text DEFAULT NULL,
  p_app_version text DEFAULT NULL,
  p_device_id uuid DEFAULT NULL
)
RETURNS TABLE(id uuid, platform text, device_name text, app_version text, updated_at timestamptz)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE
  caller_id uuid := auth.uid();
  normalized_platform text := lower(BTRIM(COALESCE(p_platform, '')));
  normalized_token text := NULLIF(BTRIM(COALESCE(p_push_token, '')), '');
  normalized_endpoint text := NULLIF(BTRIM(COALESCE(p_endpoint, '')), '');
  existing_user uuid;
  target_id uuid;
BEGIN
  IF caller_id IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF normalized_platform NOT IN ('web', 'ios', 'android') THEN RAISE EXCEPTION 'Unsupported device platform' USING ERRCODE = '22023'; END IF;
  IF normalized_platform = 'web' AND (normalized_endpoint IS NULL OR NULLIF(BTRIM(COALESCE(p_p256dh, '')), '') IS NULL OR NULLIF(BTRIM(COALESCE(p_auth_key, '')), '') IS NULL) THEN
    RAISE EXCEPTION 'Web push endpoint and keys are required' USING ERRCODE = '22023';
  END IF;
  IF normalized_platform IN ('ios', 'android') AND normalized_token IS NULL THEN
    RAISE EXCEPTION 'Native push token is required' USING ERRCODE = '22023';
  END IF;
  normalized_endpoint := COALESCE(normalized_endpoint, 'native:' || normalized_platform || ':' || normalized_token);

  IF p_device_id IS NOT NULL THEN
    SELECT user_id INTO existing_user FROM public.push_subscriptions WHERE public.push_subscriptions.id = p_device_id;
    IF existing_user IS DISTINCT FROM caller_id THEN RAISE EXCEPTION 'Device is not owned by caller' USING ERRCODE = '42501'; END IF;
    target_id := p_device_id;
  ELSE
    SELECT ps.user_id, ps.id INTO existing_user, target_id FROM public.push_subscriptions ps WHERE ps.endpoint = normalized_endpoint;
    IF target_id IS NOT NULL AND existing_user IS DISTINCT FROM caller_id THEN RAISE EXCEPTION 'Device endpoint is already registered' USING ERRCODE = '42501'; END IF;
  END IF;

  INSERT INTO public.push_subscriptions(id, user_id, endpoint, p256dh, auth_key, user_agent, platform, push_token, device_name, app_version, updated_at)
  VALUES (COALESCE(target_id, gen_random_uuid()), caller_id, normalized_endpoint,
          COALESCE(NULLIF(BTRIM(p_p256dh), ''), 'native'),
          COALESCE(NULLIF(BTRIM(p_auth_key), ''), 'native'),
          'hr.sys-client', normalized_platform, normalized_token,
          NULLIF(BTRIM(p_device_name), ''), NULLIF(BTRIM(p_app_version), ''), now())
  ON CONFLICT (endpoint) DO UPDATE SET
    user_id = EXCLUDED.user_id, p256dh = EXCLUDED.p256dh, auth_key = EXCLUDED.auth_key,
    user_agent = EXCLUDED.user_agent, platform = EXCLUDED.platform, push_token = EXCLUDED.push_token,
    device_name = EXCLUDED.device_name, app_version = EXCLUDED.app_version, updated_at = now()
    WHERE public.push_subscriptions.user_id = caller_id;

  RETURN QUERY SELECT ps.id, ps.platform, ps.device_name, ps.app_version, ps.updated_at
    FROM public.push_subscriptions ps WHERE ps.endpoint = normalized_endpoint AND ps.user_id = caller_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_notification_device_token(p_device_id uuid, p_push_token text)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE changed integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NULLIF(BTRIM(COALESCE(p_push_token, '')), '') IS NULL THEN RAISE EXCEPTION 'Push token is required' USING ERRCODE = '22023'; END IF;
  UPDATE public.push_subscriptions SET push_token = BTRIM(p_push_token), updated_at = now()
   WHERE id = p_device_id AND user_id = auth.uid();
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed = 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_notification_device(p_device_id uuid)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE changed integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  DELETE FROM public.push_subscriptions WHERE id = p_device_id AND user_id = auth.uid();
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed = 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_notification_devices()
RETURNS TABLE(id uuid, platform text, device_name text, app_version text, updated_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
  SELECT ps.id, ps.platform, ps.device_name, ps.app_version, ps.updated_at
  FROM public.push_subscriptions ps WHERE ps.user_id = auth.uid() ORDER BY ps.updated_at DESC;
$$;

REVOKE ALL ON FUNCTION public.list_my_notifications(integer,timestamptz,boolean), public.get_my_notification(uuid), public.get_my_unread_notification_count(), public.mark_notification_read(uuid), public.mark_all_notifications_read(), public.delete_my_notification(uuid), public.create_notification_secure(uuid,text,uuid), public.register_notification_device(text,text,text,text,text,text,text,uuid), public.update_notification_device_token(uuid,text), public.unregister_notification_device(uuid), public.list_my_notification_devices() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_notifications(integer,timestamptz,boolean), public.get_my_notification(uuid), public.get_my_unread_notification_count(), public.mark_notification_read(uuid), public.mark_all_notifications_read(), public.delete_my_notification(uuid), public.create_notification_secure(uuid,text,uuid), public.register_notification_device(text,text,text,text,text,text,text,uuid), public.update_notification_device_token(uuid,text), public.unregister_notification_device(uuid), public.list_my_notification_devices() TO authenticated;

COMMIT;
