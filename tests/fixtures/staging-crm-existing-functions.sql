-- Exact Staging function definitions and grants from the 2026-11-09 catalog; synthetic schema/data only.
CREATE OR REPLACE FUNCTION public.crm_is_own_generated_contact_task(p_task_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_task_id IS NOT NULL
    AND p_user_id IS NOT NULL
    AND p_user_id = auth.uid()
    AND public.is_mq20_profile(p_user_id)
    AND EXISTS (
      SELECT 1
      FROM public.crm_generated_tasks generated
      JOIN public.tasks task ON task.id = generated.task_id
      WHERE generated.task_id = p_task_id
        AND generated.kind = 'CONTACT_DISCUSSION'
        AND generated.deal_id = task.crm_deal_id
        AND task.crm_workflow_kind = 'CONTACT_DISCUSSION'
        AND task.created_by = p_user_id
        AND task.assignee_id = p_user_id
        AND p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
    );
$function$;
REVOKE ALL ON FUNCTION public.crm_is_own_generated_contact_task(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_is_own_generated_contact_task(uuid,uuid) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION public.can_access_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.tasks task
    WHERE task.id = p_task_id
      AND p_user_id IS NOT NULL
      AND (auth.uid() IS NULL OR p_user_id = auth.uid())
      AND (
        auth.uid() IS NULL
        OR NOT public.is_mq20_profile(auth.uid())
        OR public.is_ines_modani_task(task.id)
        OR public.crm_is_own_generated_contact_task(task.id, auth.uid())
      )
      AND (
        task.created_by = p_user_id
        OR task.assignee_id = p_user_id
        OR task.supervisor_id = p_user_id
        OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
        OR p_user_id = ANY(COALESCE(task.visible_to, '{}'::uuid[]))
        OR public.can_assign_tasks_company_wide(p_user_id)
        OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
        OR public.can_view_task_via_employee_grant(p_task_id, p_user_id)
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list(task.task_list_id, p_user_id))
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list_via_employee_grant(task.task_list_id, p_user_id))
      )
  );
$function$;
REVOKE ALL ON FUNCTION public.can_access_task(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_access_task(uuid,uuid) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION public.can_view_own_crm_contact_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_user_id IS NOT NULL
     AND p_user_id = auth.uid()
     AND public.is_mq20_profile(p_user_id)
     AND public.can_access_task(p_task_id, p_user_id)
     AND EXISTS (
       SELECT 1
       FROM public.tasks task
       JOIN public.crm_generated_tasks generated
         ON generated.task_id = task.id
        AND generated.deal_id = task.crm_deal_id
        AND generated.kind = 'CONTACT_DISCUSSION'
       WHERE task.id = p_task_id
         AND task.crm_workflow_kind = 'CONTACT_DISCUSSION'
         AND task.created_by = p_user_id
         AND task.assignee_id = p_user_id
         AND p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
     );
$function$;
REVOKE ALL ON FUNCTION public.can_view_own_crm_contact_task(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_own_crm_contact_task(uuid,uuid) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION public.decide_crm_design_task_approval(p_step_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_step public.crm_design_task_approval_steps%ROWTYPE;
    v_task public.tasks%ROWTYPE;
    v_deal public.crm_deals%ROWTYPE;
    v_remaining integer;
    v_notification_id uuid;
BEGIN
    p_decision := UPPER(BTRIM(COALESCE(p_decision, '')));
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'Invalid approval decision'; END IF;
    IF p_decision = 'REJECTED' AND NULLIF(BTRIM(COALESCE(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'A rejection reason is required'; END IF;
    SELECT * INTO v_step FROM public.crm_design_task_approval_steps WHERE id = p_step_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Design approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;
    UPDATE public.crm_design_task_approval_steps SET status = p_decision, decision_note = NULLIF(BTRIM(p_note), ''), decided_at = now()
    WHERE id = p_step_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval has already been decided'; END IF;
    SELECT * INTO v_task FROM public.tasks WHERE id = v_step.task_id;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_step.deal_id;
    IF p_decision = 'REJECTED' THEN
        UPDATE public.tasks SET status = 'in_progress', completion_requested_by = NULL, completion_requested_at = NULL WHERE id = v_task.id;
        UPDATE public.crm_deals SET workflow_status = 'DESIGN_REJECTED' WHERE id = v_deal.id;
        SELECT id INTO v_notification_id FROM public.notifications
        WHERE task_id = v_task.id AND user_id = v_task.assignee_id
        ORDER BY created_at DESC LIMIT 1;
        IF v_notification_id IS NULL THEN
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            VALUES (v_task.assignee_id, 'CRM Design task rejected: ' || v_task.title || '. Reason: ' || BTRIM(p_note), 'crm_design_task_rejected', v_task.id, auth.uid(), '/?view=tasks', jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note)))
            RETURNING id INTO v_notification_id;
        ELSE
            UPDATE public.notifications
               SET message = 'CRM Design task rejected: ' || v_task.title || '. Reason: ' || BTRIM(p_note),
                   event_type = 'crm_design_task_rejected',
                   metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note))
             WHERE id = v_notification_id;
        END IF;
        INSERT INTO public.task_email_outbox(notification_id, task_id, recipient_id, recipient_email, subject, message, action_url, always_send)
        SELECT v_notification_id, v_task.id, profile.id, auth_user.email, 'CRM Design task needs changes: ' || v_task.title,
               'Reason: ' || BTRIM(p_note), '/?view=tasks', true
        FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE profile.id = v_task.assignee_id AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
    ELSE
        SELECT count(*) INTO v_remaining FROM public.crm_design_task_approval_steps WHERE task_id = v_task.id AND status <> 'APPROVED';
        IF v_remaining = 0 THEN
            PERFORM set_config('app.crm_design_task_finalize', 'on', true);
            UPDATE public.tasks SET status = 'completed', completion_approved_by = auth.uid(), completion_approved_at = now() WHERE id = v_task.id;
            UPDATE public.crm_deals SET stage = 'NEGOTIATION', workflow_status = 'APPROVED' WHERE id = v_deal.id;
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            SELECT recipient, 'CRM Design approved and deal moved to Discussion: ' || v_deal.title,
                   'crm_design_task_approved', v_task.id, auth.uid(), '/?view=crm', jsonb_build_object('deal_id', v_deal.id)
            FROM unnest(array_remove(ARRAY[v_task.assignee_id, COALESCE(v_deal.created_by, v_deal.assigned_to)], NULL)) recipient;
        END IF;
    END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.decide_crm_design_task_approval(uuid,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.decide_crm_design_task_approval(uuid,text,text) TO service_role;
CREATE OR REPLACE FUNCTION public.queue_task_notification(p_task_id uuid, p_actor_id uuid, p_event_type text, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public.queue_task_notification(uuid,uuid,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.queue_task_notification(uuid,uuid,text,text) TO PUBLIC, anon, authenticated, service_role;
