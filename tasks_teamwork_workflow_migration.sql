-- Teamwork-style task hierarchy, access control, comments and notifications.
-- Run once in the Supabase SQL Editor. Safe to re-run.

BEGIN;

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS parent_task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS watchers UUID[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS visible_to UUID[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'public';

CREATE INDEX IF NOT EXISTS tasks_parent_task_id_idx ON public.tasks(parent_task_id);
CREATE INDEX IF NOT EXISTS tasks_watchers_gin_idx ON public.tasks USING gin(watchers);
CREATE INDEX IF NOT EXISTS tasks_visible_to_gin_idx ON public.tasks USING gin(visible_to);

ALTER TABLE public.task_comments
    ADD COLUMN IF NOT EXISTS parent_comment_id UUID REFERENCES public.task_comments(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS event_type TEXT,
    ADD COLUMN IF NOT EXISTS task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS action_url TEXT,
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS task_email_notifications BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TABLE IF NOT EXISTS public.task_email_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID REFERENCES public.notifications(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    recipient_email TEXT NOT NULL,
    subject TEXT NOT NULL,
    message TEXT NOT NULL,
    action_url TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at TIMESTAMPTZ
);

ALTER TABLE public.task_email_outbox ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS task_email_outbox_pending_idx
    ON public.task_email_outbox(status, created_at);

CREATE OR REPLACE FUNCTION public.is_task_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = p_user_id
          AND upper(COALESCE(p.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN')
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_task(p_task_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tasks t
        LEFT JOIN public.projects project ON project.id = t.project_id
        WHERE t.id = p_task_id
          AND p_user_id IS NOT NULL
          AND (
              public.is_task_admin(p_user_id)
              OR p_user_id IN (t.created_by, t.assignee_id, t.supervisor_id)
              OR EXISTS (
                  SELECT 1 FROM public.departments task_department
                  WHERE task_department.name = t.department
                    AND task_department.head_id = p_user_id
              )
              OR p_user_id = ANY(COALESCE(t.watchers, '{}'))
              OR p_user_id = ANY(COALESCE(t.visible_to, '{}'))
              OR p_user_id = ANY(COALESCE(project.assigned_people, '{}'))
              OR t.visibility = 'public'
              OR (
                  t.visibility = 'team'
                  AND EXISTS (
                      SELECT 1
                      FROM public.profiles viewer
                      JOIN public.profiles owner
                        ON owner.id IN (t.created_by, t.assignee_id)
                      WHERE viewer.id = p_user_id
                        AND (
                            viewer.department_id = owner.department_id
                            OR owner.manager_id = p_user_id
                            OR viewer.manager_id = owner.manager_id
                        )
                  )
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_task(p_task_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = p_task_id
          AND (
              public.is_task_admin(p_user_id)
              OR p_user_id IN (t.created_by, t.assignee_id, t.supervisor_id)
              OR EXISTS (
                  SELECT 1 FROM public.departments task_department
                  WHERE task_department.name = t.department
                    AND task_department.head_id = p_user_id
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.inherit_parent_task_access()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    parent_row public.tasks%ROWTYPE;
BEGIN
    IF NEW.parent_task_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.id IS NOT NULL AND NEW.parent_task_id = NEW.id THEN
        RAISE EXCEPTION 'A task cannot be its own parent' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO parent_row FROM public.tasks WHERE id = NEW.parent_task_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Parent task does not exist' USING ERRCODE = '23503';
    END IF;
    IF NOT public.can_view_task(parent_row.id, COALESCE(auth.uid(), NEW.created_by)) THEN
        RAISE EXCEPTION 'You cannot add a subtask to this task' USING ERRCODE = '42501';
    END IF;
    NEW.project_id := parent_row.project_id;
    NEW.visibility := parent_row.visibility;
    NEW.visible_to := COALESCE(parent_row.visible_to, '{}');
    NEW.watchers := COALESCE(parent_row.watchers, '{}');
    NEW.supervisor_id := parent_row.supervisor_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS inherit_parent_task_access_trigger ON public.tasks;
CREATE TRIGGER inherit_parent_task_access_trigger
    BEFORE INSERT OR UPDATE OF parent_task_id ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.inherit_parent_task_access();

CREATE OR REPLACE FUNCTION public.protect_task_access_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR public.is_task_admin(auth.uid()) THEN RETURN NEW; END IF;
    IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
        RAISE EXCEPTION 'The task creator cannot be changed' USING ERRCODE = '42501';
    END IF;
    IF auth.uid() <> OLD.created_by AND (
        NEW.assignee_id IS DISTINCT FROM OLD.assignee_id
        OR NEW.supervisor_id IS DISTINCT FROM OLD.supervisor_id
        OR NEW.project_id IS DISTINCT FROM OLD.project_id
        OR NEW.parent_task_id IS DISTINCT FROM OLD.parent_task_id
        OR NEW.visibility IS DISTINCT FROM OLD.visibility
        OR NEW.visible_to IS DISTINCT FROM OLD.visible_to
        OR NEW.watchers IS DISTINCT FROM OLD.watchers
    ) THEN
        RAISE EXCEPTION 'Only the task creator can change task access' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_task_access_fields_trigger ON public.tasks;
CREATE TRIGGER protect_task_access_fields_trigger
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.protect_task_access_fields();

DO $$
DECLARE policy_row RECORD;
BEGIN
    FOR policy_row IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'tasks'
    LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.tasks', policy_row.policyname); END LOOP;
    FOR policy_row IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'task_comments'
    LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.task_comments', policy_row.policyname); END LOOP;
END $$;

CREATE POLICY tasks_select_authorized ON public.tasks
    FOR SELECT TO authenticated USING (public.can_view_task(id, auth.uid()));
CREATE POLICY tasks_insert_own ON public.tasks
    FOR INSERT TO authenticated WITH CHECK (
        created_by = auth.uid()
        AND (parent_task_id IS NULL OR public.can_view_task(parent_task_id, auth.uid()))
    );
CREATE POLICY tasks_update_authorized ON public.tasks
    FOR UPDATE TO authenticated
    USING (public.can_manage_task(id, auth.uid()))
    WITH CHECK (public.can_manage_task(id, auth.uid()));
CREATE POLICY tasks_delete_creator_or_admin ON public.tasks
    FOR DELETE TO authenticated
    USING (created_by = auth.uid() OR public.is_task_admin(auth.uid()));

CREATE POLICY task_comments_select_authorized ON public.task_comments
    FOR SELECT TO authenticated USING (public.can_view_task(task_id, auth.uid()));
CREATE POLICY task_comments_insert_authorized ON public.task_comments
    FOR INSERT TO authenticated WITH CHECK (
        user_id = auth.uid() AND public.can_view_task(task_id, auth.uid())
    );
CREATE POLICY task_comments_update_own ON public.task_comments
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid() OR public.is_task_admin(auth.uid()))
    WITH CHECK (user_id = auth.uid() OR public.is_task_admin(auth.uid()));
CREATE POLICY task_comments_delete_own ON public.task_comments
    FOR DELETE TO authenticated
    USING (user_id = auth.uid() OR public.is_task_admin(auth.uid()));

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
            UNION SELECT department.head_id FROM public.departments department
                WHERE department.name = task_row.department AND department.head_id IS NOT NULL
            UNION SELECT unnest(COALESCE(project.assigned_people, '{}'))
                FROM public.projects project WHERE project.id = task_row.project_id
            UNION SELECT user_id FROM public.task_comments WHERE task_id = p_task_id
        ) recipients
        WHERE recipient_id IS DISTINCT FROM p_actor_id
    LOOP
        INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
        VALUES (recipient, p_message, p_event_type, p_task_id, p_actor_id, '/tasks-v2?task=' || p_task_id,
                jsonb_build_object('task_title', task_row.title, 'parent_task_id', task_row.parent_task_id,
                    'department_manager_id', (SELECT head_id FROM public.departments WHERE name = task_row.department LIMIT 1)))
        RETURNING * INTO notification_row;

        -- Authentication emails live in auth.users in this project. Email queue
        -- failures must never roll back the task or its in-app notification.
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

CREATE OR REPLACE FUNCTION public.notify_task_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM public.queue_task_notification(
            NEW.id, NEW.created_by,
            CASE WHEN NEW.parent_task_id IS NULL THEN 'task_created' ELSE 'subtask_created' END,
            CASE WHEN NEW.parent_task_id IS NULL THEN 'New task: ' ELSE 'New subtask: ' END || NEW.title
        );
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), CASE WHEN NEW.status = 'Pending Approval' THEN 'task_approval_requested' ELSE 'task_status_changed' END,
            CASE WHEN NEW.status = 'Pending Approval' THEN 'Completion approval requested for "' || NEW.title || '"'
            ELSE 'Task "' || NEW.title || '" moved ' ||
            CASE
                WHEN (CASE NEW.status WHEN 'todo' THEN 1 WHEN 'in_progress' THEN 2 WHEN 'review' THEN 3 WHEN 'completed' THEN 4 ELSE 0 END)
                   >= (CASE OLD.status WHEN 'todo' THEN 1 WHEN 'in_progress' THEN 2 WHEN 'review' THEN 3 WHEN 'completed' THEN 4 ELSE 0 END)
                THEN 'forward' ELSE 'backward'
            END || ' from ' || OLD.status || ' to ' || NEW.status END);
    ELSIF NEW.assignee_id IS DISTINCT FROM OLD.assignee_id THEN
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), 'task_assigned',
            'Task assigned: ' || NEW.title);
    ELSE
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), 'task_updated',
            'Task updated: ' || NEW.title);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_task_change_trigger ON public.tasks;
CREATE TRIGGER notify_task_change_trigger
    AFTER INSERT OR UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.notify_task_change();

CREATE OR REPLACE FUNCTION public.notify_task_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE task_title TEXT;
BEGIN
    SELECT title INTO task_title FROM public.tasks WHERE id = NEW.task_id;
    PERFORM public.queue_task_notification(NEW.task_id, NEW.user_id, 'task_comment',
        'New comment on "' || COALESCE(task_title, 'task') || '"');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_task_comment_trigger ON public.task_comments;
CREATE TRIGGER notify_task_comment_trigger
    AFTER INSERT ON public.task_comments
    FOR EACH ROW EXECUTE FUNCTION public.notify_task_comment();

REVOKE ALL ON FUNCTION public.is_task_admin(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_view_task(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_manage_task(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_task(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_task(UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
