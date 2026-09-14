-- Notify project To-Do assignees and expose a least-privilege project view.
BEGIN;

CREATE OR REPLACE FUNCTION public.notify_project_todo_assignees()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    recipient_id UUID;
    recipient_email TEXT;
    notification_row public.notifications%ROWTYPE;
    project_name TEXT;
    actor_name TEXT;
    action_path TEXT;
    notification_message TEXT;
    email_details JSONB;
BEGIN
    SELECT COALESCE(NULLIF(BTRIM(project.project_name), ''), 'Project')
    INTO project_name
    FROM public.projects project
    WHERE project.id = NEW.project_id;

    SELECT COALESCE(
        NULLIF(BTRIM(profile.full_name), ''),
        NULLIF(BTRIM(profile.display_name), ''),
        NULLIF(BTRIM(profile.display_name_ar), ''),
        'Project manager'
    )
    INTO actor_name
    FROM public.profiles profile
    WHERE profile.id = NEW.created_by;

    project_name := COALESCE(project_name, 'Project');
    actor_name := COALESCE(actor_name, 'Project manager');
    action_path := FORMAT('/?view=projects&project=%s&todo=%s', NEW.project_id, NEW.id);
    notification_message := FORMAT('%s assigned you the project To-Do "%s" in "%s".', actor_name, NEW.title, project_name);
    email_details := JSONB_BUILD_OBJECT(
        'Project', project_name,
        'To-Do item', NEW.title,
        'Assigned by', actor_name,
        'Due date and time', TO_CHAR(NEW.due_at AT TIME ZONE 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI')
    );

    FOREACH recipient_id IN ARRAY NEW.assignee_ids LOOP
        INSERT INTO public.notifications(
            user_id,
            message,
            event_type,
            actor_id,
            action_url,
            metadata
        )
        VALUES (
            recipient_id,
            notification_message,
            'project_todo_assigned',
            NEW.created_by,
            action_path,
            JSONB_BUILD_OBJECT(
                'project_id', NEW.project_id,
                'project_name', project_name,
                'project_todo_id', NEW.id,
                'project_todo_title', NEW.title,
                'due_at', NEW.due_at,
                'actor_name', actor_name
            )
        )
        RETURNING * INTO notification_row;

        SELECT auth_user.email
        INTO recipient_email
        FROM auth.users auth_user
        WHERE auth_user.id = recipient_id;

        IF NULLIF(BTRIM(recipient_email), '') IS NOT NULL THEN
            INSERT INTO public.task_email_outbox(
                notification_id,
                task_id,
                recipient_id,
                recipient_email,
                subject,
                message,
                action_url,
                always_send,
                context_type,
                details
            )
            VALUES (
                notification_row.id,
                NULL,
                recipient_id,
                recipient_email,
                FORMAT('Project To-Do assigned: %s', NEW.title),
                notification_message,
                action_path,
                TRUE,
                'PROJECT_TODO',
                email_details
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS project_todo_notify_assignees
    ON public.project_todos;

CREATE TRIGGER project_todo_notify_assignees
AFTER INSERT ON public.project_todos
FOR EACH ROW
EXECUTE FUNCTION public.notify_project_todo_assignees();

CREATE OR REPLACE FUNCTION public.fetch_assigned_project_todo_context(
    p_project_id UUID,
    p_todo_id UUID DEFAULT NULL
)
RETURNS TABLE (
    project_id UUID,
    project_name TEXT,
    todo_id UUID,
    todo_title TEXT,
    due_at TIMESTAMPTZ,
    status TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication is required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.project_todos assigned_todo
        WHERE assigned_todo.project_id = p_project_id
          AND (p_todo_id IS NULL OR assigned_todo.id = p_todo_id)
          AND auth.uid() = ANY(COALESCE(assigned_todo.assignee_ids, ARRAY[]::UUID[]))
    ) THEN
        RAISE EXCEPTION 'This project To-Do assignment is not available to you'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        project.id,
        project.project_name,
        assigned_todo.id,
        assigned_todo.title,
        assigned_todo.due_at,
        assigned_todo.status
    FROM public.project_todos assigned_todo
    JOIN public.projects project ON project.id = assigned_todo.project_id
    WHERE assigned_todo.project_id = p_project_id
      AND auth.uid() = ANY(COALESCE(assigned_todo.assignee_ids, ARRAY[]::UUID[]))
    ORDER BY (assigned_todo.status = 'DONE'), assigned_todo.due_at, assigned_todo.created_at;
END;
$$;

-- Ordinary project team members must use the restricted function above. Only
-- managers and executives can read the full project command-center record.
CREATE OR REPLACE FUNCTION public.is_project_portfolio_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'MANAGER', 'SUPERVISOR', 'GM', 'GENERAL MANAGER',
                  'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
              )
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) ~
                 '(^| )(MANAGER|SUPERVISOR|GM|GENERAL MANAGER|CEO|CHIEF EXECUTIVE|CHIEF EXECUTIVE OFFICER)( |$)'
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_access_project(p_project_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.projects project
        WHERE project.id = p_project_id
          AND (
              project.created_by = p_user_id
              OR project.project_manager_id = p_user_id
              OR public.is_project_portfolio_admin(p_user_id)
          )
    );
$$;

DROP POLICY IF EXISTS project_portfolio_select ON public.projects;
CREATE POLICY project_portfolio_select
ON public.projects
FOR SELECT TO authenticated
USING (
    created_by = auth.uid()
    OR project_manager_id = auth.uid()
    OR public.is_project_portfolio_admin(auth.uid())
);

REVOKE ALL ON FUNCTION public.notify_project_todo_assignees() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_assigned_project_todo_context(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_assigned_project_todo_context(UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
