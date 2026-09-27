-- Notify every assignee and watcher when an authorized Task status change is saved.
-- The trigger runs after the authoritative change_task_status/update RPC and
-- keeps notification delivery independent from the web or mobile client.
BEGIN;

CREATE OR REPLACE FUNCTION public.queue_task_status_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    recipient UUID;
    notification_row public.notifications%ROWTYPE;
    actor_name TEXT := COALESCE(public.email_profile_name(auth.uid()), 'System');
    status_label TEXT := COALESCE(NULLIF(BTRIM(NEW.status), ''), 'Unknown');
    task_message TEXT;
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status OR auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    task_message := format('Task "%s" status changed to "%s" by %s.',
        COALESCE(NEW.title, 'Untitled task'), status_label, actor_name);

    FOR recipient IN
        SELECT DISTINCT recipient_id
        FROM (
            SELECT NEW.assignee_id AS recipient_id
            UNION ALL
            SELECT unnest(COALESCE(NEW.assignee_ids, '{}'::UUID[]))
            UNION ALL
            SELECT unnest(COALESCE(NEW.watchers, '{}'::UUID[]))
        ) recipients
        WHERE recipient_id IS NOT NULL
          AND recipient_id IS DISTINCT FROM auth.uid()
    LOOP
        INSERT INTO public.notifications(
            user_id, message, event_type, task_id, actor_id, action_url, metadata
        )
        VALUES (
            recipient,
            task_message,
            'task_status_changed',
            NEW.id,
            auth.uid(),
            '/?view=tasks&task=' || NEW.id,
            jsonb_build_object(
                'task_title', NEW.title,
                'from_status', OLD.status,
                'to_status', NEW.status,
                'actor_name', actor_name
            )
        )
        RETURNING * INTO notification_row;

        BEGIN
            INSERT INTO public.task_email_outbox(
                notification_id, task_id, recipient_id, recipient_email,
                subject, message, action_url, always_send, context_type, details
            )
            SELECT
                notification_row.id,
                NEW.id,
                profile.id,
                auth_user.email,
                'Task status updated: ' || COALESCE(NEW.title, 'Untitled task'),
                task_message,
                '/?view=tasks&task=' || NEW.id,
                TRUE,
                'TASK',
                jsonb_strip_nulls(jsonb_build_object(
                    'Task title', NEW.title,
                    'Task creator', public.email_profile_name(NEW.created_by),
                    'Updated by', actor_name,
                    'Assigned to', public.email_profile_name(NEW.assignee_id),
                    'From status', OLD.status,
                    'To status', NEW.status,
                    'Event', 'task_status_changed'
                ))
            FROM public.profiles profile
            JOIN auth.users auth_user ON auth_user.id = profile.id
            WHERE profile.id = recipient
              AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Unable to queue Task status email for recipient %: %', recipient, SQLERRM;
        END;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_status_notification_trigger ON public.tasks;
CREATE TRIGGER task_status_notification_trigger
    AFTER UPDATE OF status ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.queue_task_status_notification();

REVOKE ALL ON FUNCTION public.queue_task_status_notification() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
