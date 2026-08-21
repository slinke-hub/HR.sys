-- Hotfix for projects where user email is stored in auth.users rather than profiles.
-- Run this once in the Supabase SQL Editor. It is safe to re-run.

CREATE OR REPLACE FUNCTION public.queue_task_notification(
    p_task_id UUID,
    p_actor_id UUID,
    p_event_type TEXT,
    p_message TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    task_row public.tasks%ROWTYPE;
    recipient UUID;
    notification_row public.notifications%ROWTYPE;
BEGIN
    SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id;
    IF NOT FOUND THEN RETURN; END IF;

    FOR recipient IN
        SELECT DISTINCT recipient_id FROM (
            SELECT unnest(array_remove(ARRAY[task_row.created_by, task_row.assignee_id, task_row.supervisor_id], NULL)) AS recipient_id
            UNION SELECT unnest(COALESCE(task_row.watchers, '{}'))
            UNION SELECT unnest(COALESCE(task_row.visible_to, '{}'))
            UNION SELECT unnest(COALESCE(project.assigned_people, '{}'))
                FROM public.projects project WHERE project.id = task_row.project_id
            UNION SELECT user_id FROM public.task_comments WHERE task_id = p_task_id
        ) recipients
        WHERE recipient_id IS DISTINCT FROM p_actor_id
    LOOP
        INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
        VALUES (recipient, p_message, p_event_type, p_task_id, p_actor_id, '/tasks-v2?task=' || p_task_id,
                jsonb_build_object('task_title', task_row.title, 'parent_task_id', task_row.parent_task_id))
        RETURNING * INTO notification_row;

        BEGIN
            INSERT INTO public.task_email_outbox(notification_id, recipient_id, recipient_email, subject, message, action_url)
            SELECT notification_row.id, profile.id, auth_user.email,
                   CASE WHEN p_event_type = 'task_comment' THEN 'New comment: ' ELSE 'Task update: ' END || task_row.title,
                   p_message, notification_row.action_url
            FROM public.profiles profile
            JOIN auth.users auth_user ON auth_user.id = profile.id
            WHERE profile.id = recipient
              AND profile.task_email_notifications = TRUE
              AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Unable to queue task email for recipient %: %', recipient, SQLERRM;
        END;
    END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
