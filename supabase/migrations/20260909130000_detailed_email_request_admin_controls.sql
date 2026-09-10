-- Rich email context, employee-request email delivery, and guarded admin deletion.
BEGIN;

ALTER TABLE public.task_email_outbox
    ADD COLUMN IF NOT EXISTS context_type TEXT NOT NULL DEFAULT 'TASK',
    ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::JSONB;

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS event_type TEXT,
    ADD COLUMN IF NOT EXISTS action_url TEXT,
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::JSONB;

CREATE OR REPLACE FUNCTION public.email_profile_name(p_profile_id UUID)
RETURNS TEXT LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT COALESCE(
        NULLIF(BTRIM(profile.full_name), ''),
        NULLIF(BTRIM(profile.display_name), ''),
        NULLIF(BTRIM(profile.display_name_ar), ''),
        'Unknown employee'
    )
    FROM public.profiles profile WHERE profile.id = p_profile_id;
$$;

CREATE OR REPLACE FUNCTION public.queue_task_notification(
    p_task_id UUID,
    p_actor_id UUID,
    p_event_type TEXT,
    p_message TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    task_row public.tasks%ROWTYPE;
    recipient UUID;
    notification_row public.notifications%ROWTYPE;
    latest_comment TEXT;
    attachment_links JSONB := '[]'::JSONB;
    task_details JSONB;
BEGIN
    SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF p_event_type = 'task_comment' THEN
        SELECT content INTO latest_comment FROM public.task_comments
        WHERE task_id = p_task_id AND user_id = p_actor_id
        ORDER BY created_at DESC LIMIT 1;
    END IF;

    SELECT COALESCE(jsonb_agg(DISTINCT link) FILTER (WHERE link IS NOT NULL AND BTRIM(link) <> ''), '[]'::JSONB)
    INTO attachment_links
    FROM (
        SELECT jsonb_array_elements_text(COALESCE(to_jsonb(task_row.content_links), '[]'::JSONB)) AS link
        UNION ALL
        SELECT jsonb_array_elements_text(COALESCE(to_jsonb(task_row.submission_links), '[]'::JSONB)) AS link
    ) task_links;

    task_details := jsonb_strip_nulls(jsonb_build_object(
        'Task title', task_row.title,
        'Description', task_row.description,
        'Task creator', public.email_profile_name(task_row.created_by),
        'Updated by', public.email_profile_name(p_actor_id),
        'Assigned to', public.email_profile_name(task_row.assignee_id),
        'Supervisor', public.email_profile_name(task_row.supervisor_id),
        'Status', task_row.status,
        'Priority', task_row.priority,
        'Department', task_row.department,
        'Category', task_row.category,
        'Start date', task_row.start_date,
        'Due date', COALESCE(task_row.due_date, task_row.end_date),
        'Estimated time', task_row.estimated_time,
        'Event', p_event_type,
        'Comment', latest_comment
    ));

    FOR recipient IN
        SELECT DISTINCT recipient_id FROM (
            SELECT unnest(array_remove(ARRAY[task_row.created_by, task_row.assignee_id, task_row.supervisor_id], NULL)) AS recipient_id
            UNION SELECT unnest(COALESCE(task_row.watchers, '{}'))
            UNION SELECT unnest(COALESCE(task_row.visible_to, '{}'))
            UNION SELECT department.head_id FROM public.departments department
                WHERE department.name = task_row.department AND department.head_id IS NOT NULL
            UNION SELECT unnest(COALESCE(project.assigned_people, '{}')) FROM public.projects project WHERE project.id = task_row.project_id
            UNION SELECT user_id FROM public.task_comments WHERE task_id = p_task_id
            UNION SELECT profile.id FROM public.profiles profile
                WHERE UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
        ) recipients
        WHERE recipient_id IS DISTINCT FROM p_actor_id
           OR EXISTS (
               SELECT 1 FROM public.profiles administrator
               WHERE administrator.id = recipient_id
                 AND UPPER(REPLACE(COALESCE(administrator.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
           )
    LOOP
        INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
        VALUES (
            recipient, p_message, p_event_type, p_task_id, p_actor_id,
            '/tasks-v2?task=' || p_task_id,
            jsonb_build_object('task_title', task_row.title, 'parent_task_id', task_row.parent_task_id,
                'department_manager_id', (SELECT head_id FROM public.departments WHERE name = task_row.department LIMIT 1),
                'comment_text', latest_comment, 'attachment_links', attachment_links,
                'notify_via_email', task_row.notify_via_email, 'actor_name', public.email_profile_name(p_actor_id),
                'creator_name', public.email_profile_name(task_row.created_by))
        ) RETURNING * INTO notification_row;

        BEGIN
            INSERT INTO public.task_email_outbox(
                notification_id, task_id, recipient_id, recipient_email, subject, message,
                action_url, comment_text, attachment_links, always_send, context_type, details
            )
            SELECT notification_row.id, task_row.id, profile.id, auth_user.email,
                   CASE WHEN p_event_type = 'task_comment' THEN 'New comment: ' ELSE 'Task update: ' END || task_row.title,
                   p_message, notification_row.action_url, latest_comment, attachment_links,
                   UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'),
                   'TASK', task_details
            FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
            WHERE profile.id = recipient
              AND (
                  UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
                  OR (task_row.notify_via_email IS TRUE AND profile.task_email_notifications = TRUE)
              )
              AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Unable to queue detailed task email for recipient %: %', recipient, SQLERRM;
        END;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_request_notification(p_user_id UUID, p_message TEXT, p_event_type TEXT, p_workflow_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    notification_row public.notifications%ROWTYPE;
    workflow_row public.request_approval_workflows%ROWTYPE;
    source_details JSONB := '{}'::JSONB;
    email_details JSONB;
    actor_id UUID := auth.uid();
BEGIN
    SELECT * INTO workflow_row FROM public.request_approval_workflows WHERE id = p_workflow_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF workflow_row.source_table IN ('requests', 'leave_requests', 'document_requests', 'expenses') THEN
        EXECUTE format('SELECT to_jsonb(source_row) FROM public.%I source_row WHERE id = $1', workflow_row.source_table)
        INTO source_details USING workflow_row.source_id;
    END IF;
    source_details := COALESCE(source_details, '{}'::JSONB)
        - 'id' - 'employee_id' - 'is_archived' - 'receipt_base64' - 'attachment_base64' - 'file_data';
    email_details := jsonb_strip_nulls(jsonb_build_object(
        'Request type', workflow_row.request_type,
        'Employee', public.email_profile_name(workflow_row.employee_id),
        'Action by', public.email_profile_name(actor_id),
        'Approval status', workflow_row.status,
        'Current approval step', workflow_row.current_step,
        'Event', p_event_type,
        'Request details', source_details
    ));

    INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
    VALUES (
        p_user_id, p_message, p_event_type, actor_id, '/?view=requests',
        jsonb_build_object('workflow_id', p_workflow_id, 'request_type', workflow_row.request_type,
            'source_table', workflow_row.source_table, 'source_id', workflow_row.source_id,
            'employee_name', public.email_profile_name(workflow_row.employee_id),
            'actor_name', public.email_profile_name(actor_id))
    ) RETURNING * INTO notification_row;

    BEGIN
        INSERT INTO public.task_email_outbox(
            notification_id, task_id, recipient_id, recipient_email, subject, message,
            action_url, always_send, context_type, details
        )
        SELECT notification_row.id, NULL, profile.id, auth_user.email,
               'Employee request update: ' || workflow_row.request_type,
               p_message, notification_row.action_url, TRUE, 'EMPLOYEE_REQUEST', email_details
        FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE profile.id = p_user_id
          AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Unable to queue employee request email: %', SQLERRM;
    END;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_employee_request_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = p_user_id AND profile.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) IN
                 ('GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER')
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_employee_request(p_source_table TEXT, p_source_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE deleted_count INTEGER := 0;
BEGIN
    IF NOT public.is_employee_request_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only administrators can delete employee requests' USING ERRCODE = '42501';
    END IF;
    IF p_source_table NOT IN ('requests', 'leave_requests', 'document_requests', 'expenses') THEN
        RAISE EXCEPTION 'Unsupported employee request type';
    END IF;

    DELETE FROM public.request_approval_workflows
    WHERE source_table = p_source_table AND source_id = p_source_id;
    DELETE FROM public.notifications
    WHERE metadata->>'source_table' = p_source_table AND metadata->>'source_id' = p_source_id::TEXT;
    EXECUTE format('DELETE FROM public.%I WHERE id = $1', p_source_table) USING p_source_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    IF deleted_count = 0 THEN RAISE EXCEPTION 'Employee request not found'; END IF;
    RETURN jsonb_build_object('deleted', TRUE, 'source_table', p_source_table, 'source_id', p_source_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_employee_request(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_employee_request(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_employee_request_admin(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.email_profile_name(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
