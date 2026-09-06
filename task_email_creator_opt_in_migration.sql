-- Make task email notifications opt-in per task, with a mandatory administrator exception.
-- In-app notifications remain enabled.

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS notify_via_email BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.tasks.notify_via_email IS
    'True only when the task creator explicitly selected Notify via email during creation.';

ALTER TABLE public.task_email_outbox
    ADD COLUMN IF NOT EXISTS task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS always_send BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.task_email_outbox outbox
SET task_id = notification.task_id
FROM public.notifications notification
WHERE outbox.notification_id = notification.id
  AND outbox.task_id IS NULL;

UPDATE public.task_email_outbox outbox
SET always_send = TRUE
FROM public.profiles profile
WHERE profile.id = outbox.recipient_id
  AND UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' '))
      IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN');

ALTER TABLE public.task_email_outbox
    DROP CONSTRAINT IF EXISTS task_email_outbox_status_check;

ALTER TABLE public.task_email_outbox
    ADD CONSTRAINT task_email_outbox_status_check
    CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled'));

-- Do not allow messages queued by the former automatic behavior to be sent.
UPDATE public.task_email_outbox outbox
SET status = 'cancelled',
    last_error = 'Email was not requested by the task creator.'
FROM public.tasks task
WHERE outbox.task_id = task.id
  AND outbox.status IN ('pending', 'processing')
  AND outbox.always_send IS NOT TRUE
  AND task.notify_via_email IS NOT TRUE;

UPDATE public.task_email_outbox
SET status = 'cancelled',
    last_error = 'Email opt-in could not be verified.'
WHERE task_id IS NULL
  AND always_send IS NOT TRUE
  AND status IN ('pending', 'processing');

-- If this migration was applied before the administrator exception was added,
-- restore any administrator messages that it previously cancelled.
UPDATE public.task_email_outbox
SET status = 'pending',
    last_error = NULL
WHERE always_send IS TRUE
  AND status = 'cancelled'
  AND last_error IN (
      'Email was not requested by the task creator.',
      'Email opt-in could not be verified.'
  );

CREATE INDEX IF NOT EXISTS task_email_outbox_task_id_idx
    ON public.task_email_outbox(task_id);

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
    latest_comment TEXT;
    attachment_links JSONB := '[]'::jsonb;
BEGIN
    SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF p_event_type = 'task_comment' THEN
        SELECT content INTO latest_comment
        FROM public.task_comments
        WHERE task_id = p_task_id AND user_id = p_actor_id
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    SELECT COALESCE(jsonb_agg(DISTINCT link) FILTER (WHERE link IS NOT NULL AND BTRIM(link) <> ''), '[]'::jsonb)
    INTO attachment_links
    FROM (
        SELECT jsonb_array_elements_text(COALESCE(to_jsonb(task_row.content_links), '[]'::jsonb)) AS link
        UNION ALL
        SELECT jsonb_array_elements_text(COALESCE(to_jsonb(task_row.submission_links), '[]'::jsonb)) AS link
    ) task_links;

    FOR recipient IN
        SELECT DISTINCT recipient_id FROM (
            SELECT unnest(array_remove(ARRAY[task_row.created_by, task_row.assignee_id, task_row.supervisor_id], NULL)) AS recipient_id
            UNION SELECT unnest(COALESCE(task_row.watchers, '{}'))
            UNION SELECT unnest(COALESCE(task_row.visible_to, '{}'))
            UNION SELECT department.head_id FROM public.departments department
                WHERE department.name = task_row.department AND department.head_id IS NOT NULL
            UNION SELECT unnest(COALESCE(project.assigned_people, '{}'))
                FROM public.projects project WHERE project.id = task_row.project_id
            UNION SELECT user_id FROM public.task_comments WHERE task_id = p_task_id
            UNION SELECT profile.id FROM public.profiles profile
                WHERE UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' '))
                    IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
        ) recipients
        WHERE recipient_id IS DISTINCT FROM p_actor_id
           OR EXISTS (
               SELECT 1 FROM public.profiles administrator
               WHERE administrator.id = recipient_id
                 AND UPPER(REPLACE(COALESCE(administrator.role, ''), '_', ' '))
                     IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
           )
    LOOP
        INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
        VALUES (
            recipient, p_message, p_event_type, p_task_id, p_actor_id,
            '/tasks-v2?task=' || p_task_id,
            jsonb_build_object(
                'task_title', task_row.title,
                'parent_task_id', task_row.parent_task_id,
                'department_manager_id', (SELECT head_id FROM public.departments WHERE name = task_row.department LIMIT 1),
                'comment_text', latest_comment,
                'attachment_links', attachment_links,
                'notify_via_email', task_row.notify_via_email
            )
        ) RETURNING * INTO notification_row;

        -- Administrators always receive task email. Everyone else requires
        -- both the creator's task-level opt-in and their recipient preference.
        BEGIN
            INSERT INTO public.task_email_outbox(
                notification_id, task_id, recipient_id, recipient_email, subject, message,
                action_url, comment_text, attachment_links, always_send
            )
            SELECT notification_row.id, task_row.id, profile.id, auth_user.email,
                   CASE WHEN p_event_type = 'task_comment' THEN 'New comment: ' ELSE 'Task update: ' END || task_row.title,
                   p_message, notification_row.action_url, latest_comment, attachment_links,
                   UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' '))
                       IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
            FROM public.profiles profile
            JOIN auth.users auth_user ON auth_user.id = profile.id
            WHERE profile.id = recipient
              AND (
                  UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' '))
                      IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
                  OR (task_row.notify_via_email IS TRUE AND profile.task_email_notifications = TRUE)
              )
              AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Unable to queue task email for recipient %: %', recipient, SQLERRM;
        END;
    END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
