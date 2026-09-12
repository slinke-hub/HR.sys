-- Migration: Ensure task_attachments table exists and email notifications safely include attachments and photos
BEGIN;

-- 1. Create task_attachments table if it does not exist
CREATE TABLE IF NOT EXISTS public.task_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    file_url TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_type TEXT,
    file_size BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.task_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view task attachments" ON public.task_attachments;
CREATE POLICY "Users can view task attachments"
    ON public.task_attachments FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Authenticated users can upload attachments" ON public.task_attachments;
CREATE POLICY "Authenticated users can upload attachments"
    ON public.task_attachments FOR INSERT
    TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "Uploaders can delete their attachments" ON public.task_attachments;
CREATE POLICY "Uploaders can delete their attachments"
    ON public.task_attachments FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

GRANT ALL ON TABLE public.task_attachments TO authenticated, service_role;

-- 2. Update queue_task_notification to aggregate task attachments safely
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
    attachment_links JSONB := '[]'::JSONB;
    db_file_links JSONB := '[]'::JSONB;
    task_details JSONB;
BEGIN
    SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF p_event_type = 'task_comment' THEN
        IF to_regclass('public.task_comments') IS NOT NULL THEN
            SELECT content INTO latest_comment
            FROM public.task_comments
            WHERE task_id = p_task_id AND user_id = p_actor_id
            ORDER BY created_at DESC LIMIT 1;

            SELECT COALESCE(jsonb_agg(
                CASE 
                    WHEN jsonb_typeof(elem) = 'object' AND elem ? 'url' THEN elem->>'url'
                    WHEN jsonb_typeof(elem) = 'object' AND elem ? 'file_url' THEN elem->>'file_url'
                    ELSE elem #>> '{}'
                END
            ) FILTER (WHERE elem IS NOT NULL), '[]'::JSONB)
            INTO db_file_links
            FROM (
                SELECT elem
                FROM public.task_comments tc,
                     jsonb_array_elements(COALESCE(tc.attachments, '[]'::JSONB)) elem
                WHERE tc.task_id = p_task_id AND tc.user_id = p_actor_id
                ORDER BY tc.created_at DESC LIMIT 1
            ) sub;
        END IF;
    END IF;

    -- Safely read task_attachments if table exists
    IF to_regclass('public.task_attachments') IS NOT NULL THEN
        EXECUTE 'SELECT COALESCE(jsonb_agg(file_url) FILTER (WHERE file_url IS NOT NULL AND BTRIM(file_url) <> ''''), ''[]''::JSONB) FROM public.task_attachments WHERE task_id = $1'
        INTO db_file_links
        USING p_task_id;
    END IF;
    db_file_links := COALESCE(db_file_links, '[]'::JSONB);

    -- Aggregate all content links, submission links, uploaded files, and source links
    SELECT COALESCE(jsonb_agg(DISTINCT link) FILTER (WHERE link IS NOT NULL AND BTRIM(link) <> ''), '[]'::JSONB)
    INTO attachment_links
    FROM (
        SELECT jsonb_array_elements_text(COALESCE(to_jsonb(task_row.content_links), '[]'::JSONB)) AS link
        UNION ALL
        SELECT jsonb_array_elements_text(COALESCE(to_jsonb(task_row.submission_links), '[]'::JSONB)) AS link
        UNION ALL
        SELECT task_row.upload_link AS link WHERE task_row.upload_link IS NOT NULL
        UNION ALL
        SELECT task_row.source_link AS link WHERE task_row.source_link IS NOT NULL
        UNION ALL
        SELECT jsonb_array_elements_text(db_file_links) AS link
        UNION ALL
        SELECT jsonb_array_elements_text(
            CASE 
                WHEN jsonb_typeof(COALESCE(to_jsonb(task_row.attachments), '[]'::JSONB)) = 'array' 
                THEN to_jsonb(task_row.attachments) 
                ELSE '[]'::JSONB 
            END
        ) AS link
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
            '/?view=tasks&task=' || p_task_id,
            jsonb_build_object(
                'task_title', task_row.title,
                'parent_task_id', task_row.parent_task_id,
                'department_manager_id', (SELECT head_id FROM public.departments WHERE name = task_row.department LIMIT 1),
                'comment_text', latest_comment,
                'attachment_links', attachment_links,
                'notify_via_email', task_row.notify_via_email,
                'actor_name', public.email_profile_name(p_actor_id),
                'creator_name', public.email_profile_name(task_row.created_by)
            )
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

-- 3. Update queue_request_notification to pass receipt/attachments into task_email_outbox
CREATE OR REPLACE FUNCTION public.queue_request_notification(
    p_user_id UUID,
    p_message TEXT,
    p_event_type TEXT,
    p_workflow_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    notification_row public.notifications%ROWTYPE;
    workflow_row public.request_approval_workflows%ROWTYPE;
    source_details JSONB := '{}'::JSONB;
    email_details JSONB;
    actor_id UUID := auth.uid();
    v_attachment_links JSONB := '[]'::JSONB;
BEGIN
    SELECT * INTO workflow_row FROM public.request_approval_workflows WHERE id = p_workflow_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF workflow_row.source_table IN ('requests', 'leave_requests', 'document_requests', 'expenses') THEN
        EXECUTE format('SELECT to_jsonb(source_row) FROM public.%I source_row WHERE id = $1', workflow_row.source_table)
        INTO source_details USING workflow_row.source_id;
    END IF;

    -- Extract expense receipt if available
    IF workflow_row.source_table = 'expenses' THEN
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'url', receipt_base64,
                    'name', 'Receipt - ' || COALESCE(description, 'Expense')
                )
            ),
            '[]'::JSONB
        )
        INTO v_attachment_links
        FROM public.expenses
        WHERE id = workflow_row.source_id AND receipt_base64 IS NOT NULL AND BTRIM(receipt_base64) <> '';
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
        p_user_id, p_message, p_event_type, actor_id, '/?view=requests&request=' || workflow_row.source_id,
        jsonb_build_object(
            'workflow_id', p_workflow_id,
            'request_type', workflow_row.request_type,
            'source_table', workflow_row.source_table,
            'source_id', workflow_row.source_id,
            'employee_name', public.email_profile_name(workflow_row.employee_id),
            'actor_name', public.email_profile_name(actor_id),
            'attachment_links', v_attachment_links
        )
    ) RETURNING * INTO notification_row;

    BEGIN
        INSERT INTO public.task_email_outbox(
            notification_id, task_id, recipient_id, recipient_email, subject, message,
            action_url, attachment_links, always_send, context_type, details
        )
        SELECT notification_row.id, NULL, profile.id, auth_user.email,
               'Employee request update: ' || workflow_row.request_type,
               p_message, notification_row.action_url, v_attachment_links, TRUE, 'EMPLOYEE_REQUEST', email_details
        FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE profile.id = p_user_id
          AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Unable to queue employee request email: %', SQLERRM;
    END;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
