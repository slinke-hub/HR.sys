-- Shared server-side business-logic paths for the web client and future native
-- clients. RLS remains in force for all other table access.
BEGIN;

-- Shared attachment metadata contract. Storage buckets remain private; this
-- trigger rejects oversized/unsafe metadata before a row can reference a file.
ALTER TABLE public.task_attachments
    ADD COLUMN IF NOT EXISTS file_type text,
    ADD COLUMN IF NOT EXISTS file_size bigint;
ALTER TABLE public.crm_deal_attachments
    ADD COLUMN IF NOT EXISTS file_type text,
    ADD COLUMN IF NOT EXISTS file_size bigint;

CREATE OR REPLACE FUNCTION public.validate_shared_attachment_metadata()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_type text := LOWER(BTRIM(COALESCE(NEW.file_type, '')));
    v_name text := LOWER(BTRIM(COALESCE(NEW.file_name, '')));
    v_url text := BTRIM(COALESCE(NEW.file_url, ''));
BEGIN
    IF NEW.file_size IS NOT NULL AND (NEW.file_size < 0 OR NEW.file_size > 26214400) THEN
        RAISE EXCEPTION 'Attachment exceeds the 25 MB limit' USING ERRCODE = '22023';
    END IF;
    IF v_type <> '' AND v_type NOT IN (
        'application/pdf','image/jpeg','image/png','image/webp','text/plain',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ) THEN
        RAISE EXCEPTION 'This file type is not allowed' USING ERRCODE = '22023';
    END IF;
    IF v_name ~ '\.(exe|com|bat|cmd|scr|js|vbs|ps1|sh|dll)(\.|$)' THEN
        RAISE EXCEPTION 'Executable attachments are not allowed' USING ERRCODE = '22023';
    END IF;
    IF TG_TABLE_NAME = 'task_attachments' AND v_url !~ '^storage://task-attachments/[A-Za-z0-9._/-]+$' THEN
        RAISE EXCEPTION 'Invalid task attachment storage reference' USING ERRCODE = '22023';
    ELSIF TG_TABLE_NAME = 'crm_deal_attachments' AND v_url !~ '^storage://crm-deal-files/[A-Za-z0-9._/-]+$' THEN
        RAISE EXCEPTION 'Invalid deal attachment storage reference' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_task_attachment_metadata ON public.task_attachments;
CREATE TRIGGER validate_task_attachment_metadata
BEFORE INSERT OR UPDATE ON public.task_attachments
FOR EACH ROW EXECUTE FUNCTION public.validate_shared_attachment_metadata();
DROP TRIGGER IF EXISTS validate_crm_deal_attachment_metadata ON public.crm_deal_attachments;
CREATE TRIGGER validate_crm_deal_attachment_metadata
BEFORE INSERT OR UPDATE ON public.crm_deal_attachments
FOR EACH ROW EXECUTE FUNCTION public.validate_shared_attachment_metadata();
REVOKE ALL ON FUNCTION public.validate_shared_attachment_metadata() FROM PUBLIC, anon, authenticated;

-- Central task access predicates. These mirror the existing Task Manager
-- visibility/list/department rules and are reused by every task RPC and child
-- record policy below.
CREATE OR REPLACE FUNCTION public.can_access_task(
    p_task_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM public.tasks task
         WHERE task.id = p_task_id
           AND (
               task.created_by = p_user_id
               OR task.assignee_id = p_user_id
               OR task.supervisor_id = p_user_id
               OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
               OR public.can_assign_tasks_company_wide(p_user_id)
               OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
               OR (task.task_list_id IS NOT NULL AND public.can_view_task_list(task.task_list_id, p_user_id))
               OR (task.task_list_id IS NOT NULL AND public.can_view_task_list_via_employee_grant(task.task_list_id, p_user_id))
           )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_task(
    p_task_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM public.tasks task
          LEFT JOIN public.task_lists task_list ON task_list.id = task.task_list_id
         WHERE task.id = p_task_id
           AND (
               task.created_by = p_user_id
               OR task.assignee_id = p_user_id
               OR task.supervisor_id = p_user_id
               OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
               OR public.can_assign_tasks_company_wide(p_user_id)
               OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
               OR p_user_id = ANY(COALESCE(task_list.can_delete_users, '{}'::uuid[]))
           )
    );
$$;

CREATE OR REPLACE FUNCTION public.list_accessible_tasks_secure()
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT to_jsonb(task)
        || jsonb_build_object(
            'assignee', CASE WHEN assignee.id IS NULL THEN NULL ELSE to_jsonb(assignee) END,
            'profiles', CASE WHEN assignee.id IS NULL THEN NULL ELSE to_jsonb(assignee) END,
            'projects', CASE WHEN project.id IS NULL THEN NULL ELSE jsonb_build_object('id', project.id, 'project_name', project.project_name) END
        )
      FROM public.tasks task
      LEFT JOIN public.profiles assignee ON assignee.id = task.assignee_id
      LEFT JOIN public.projects project ON project.id = task.project_id
     WHERE auth.uid() IS NOT NULL AND public.can_access_task(task.id, auth.uid())
     ORDER BY task.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_task_secure(p_task_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT item
      FROM public.list_accessible_tasks_secure() item
     WHERE item->>'id' = p_task_id::text
     LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.create_task_secure(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_assignees uuid[];
    v_assignee_id uuid;
    v_project_id uuid;
    v_task_list_id uuid;
    v_payload jsonb := COALESCE(p_payload, '{}'::jsonb);
    v_result jsonb;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    IF NULLIF(BTRIM(v_payload->>'title'), '') IS NULL THEN
        RAISE EXCEPTION 'Task title is required' USING ERRCODE = '22023';
    END IF;
    v_assignee_id := NULLIF(v_payload->>'assignee_id', '')::uuid;
    v_assignees := ARRAY(
        SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(v_payload->'assignee_ids', '[]'::jsonb)) value
    );
    IF v_assignee_id IS NOT NULL AND NOT (v_assignee_id = ANY(COALESCE(v_assignees, '{}'::uuid[]))) THEN
        v_assignees := array_prepend(v_assignee_id, COALESCE(v_assignees, '{}'::uuid[]));
    END IF;
    IF EXISTS (
        SELECT 1 FROM UNNEST(COALESCE(v_assignees, '{}'::uuid[])) assignee_id
        WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile WHERE profile.id = assignee_id AND profile.is_active IS DISTINCT FROM false)
    ) THEN RAISE EXCEPTION 'Every assignee must be an active employee' USING ERRCODE = '22023'; END IF;
    v_project_id := NULLIF(v_payload->>'project_id', '')::uuid;
    v_task_list_id := NULLIF(v_payload->>'task_list_id', '')::uuid;
    IF v_project_id IS NOT NULL AND NOT public.can_access_project(v_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    IF v_task_list_id IS NOT NULL AND NOT public.can_add_task_to_list(v_task_list_id, auth.uid()) THEN
        RAISE EXCEPTION 'Task-list access denied' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.tasks (
        title, description, assignee_id, assignee_ids, supervisor_id, created_by,
        due_date, status, priority, category, title_i18n, description_i18n,
        start_date, end_date, estimated_time, visibility, project_id, tags,
        visible_to, content_type, source_link, upload_link, department, sub_type,
        watchers, parent_task_id, marketing_department, content_links,
        submission_links, delivery_status, task_list_id, repeat_type,
        repeat_interval, notify_via_email, crm_deal_id, crm_workflow_kind
    )
    VALUES (
        BTRIM(v_payload->>'title'), NULLIF(v_payload->>'description', ''),
        v_assignee_id, COALESCE(v_assignees, '{}'::uuid[]),
        NULLIF(v_payload->>'supervisor_id', '')::uuid, auth.uid(),
        NULLIF(v_payload->>'due_date', '')::date,
        COALESCE(NULLIF(v_payload->>'status', ''), 'todo'),
        COALESCE(NULLIF(v_payload->>'priority', ''), 'medium'),
        COALESCE(NULLIF(v_payload->>'category', ''), 'General'),
        COALESCE(v_payload->'title_i18n', '{}'::jsonb),
        COALESCE(v_payload->'description_i18n', '{}'::jsonb),
        NULLIF(v_payload->>'start_date', '')::date,
        NULLIF(v_payload->>'end_date', '')::date,
        NULLIF(v_payload->>'estimated_time', '')::integer,
        COALESCE(NULLIF(v_payload->>'visibility', ''), 'public'),
        v_project_id,
        ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(v_payload->'tags', '[]'::jsonb)) value),
        ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(v_payload->'visible_to', '[]'::jsonb)) value),
        NULLIF(v_payload->>'content_type', ''), NULLIF(v_payload->>'source_link', ''),
        NULLIF(v_payload->>'upload_link', ''), NULLIF(v_payload->>'department', ''),
        NULLIF(v_payload->>'sub_type', ''),
        ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(v_payload->'watchers', '[]'::jsonb)) value),
        NULLIF(v_payload->>'parent_task_id', '')::uuid,
        NULLIF(v_payload->>'marketing_department', ''),
        ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(v_payload->'content_links', '[]'::jsonb)) value),
        ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(v_payload->'submission_links', '[]'::jsonb)) value),
        NULLIF(v_payload->>'delivery_status', ''), v_task_list_id,
        COALESCE(NULLIF(v_payload->>'repeat_type', ''), 'NONE'),
        COALESCE(NULLIF(v_payload->>'repeat_interval', '')::integer, 1),
        COALESCE((v_payload->>'notify_via_email')::boolean, false),
        NULLIF(v_payload->>'crm_deal_id', '')::uuid,
        NULLIF(v_payload->>'crm_workflow_kind', '')
    )
    RETURNING to_jsonb(tasks) INTO v_result;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_task_secure(p_task_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_next public.tasks%ROWTYPE;
    v_safe jsonb := '{}'::jsonb;
    v_result jsonb;
    v_key text;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_manage_task(p_task_id, auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to update this task' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
    FOR v_key IN SELECT unnest(ARRAY[
        'title','description','due_date','priority','category','title_i18n',
        'description_i18n','start_date','end_date','estimated_time','visibility',
        'project_id','tags','visible_to','content_type','source_link','upload_link',
        'department','sub_type','watchers','parent_task_id','marketing_department',
        'content_links','submission_links','delivery_status','task_list_id',
        'repeat_type','repeat_interval','notify_via_email','crm_deal_id','crm_workflow_kind'
    ]) LOOP
        IF p_patch ? v_key THEN v_safe := v_safe || jsonb_build_object(v_key, p_patch->v_key); END IF;
    END LOOP;
    IF v_safe ? 'title' AND NULLIF(BTRIM(v_safe->>'title'), '') IS NULL THEN
        RAISE EXCEPTION 'Task title is required' USING ERRCODE = '22023';
    END IF;
    IF v_safe ? 'project_id' AND NULLIF(v_safe->>'project_id', '') IS NOT NULL
       AND NOT public.can_access_project((v_safe->>'project_id')::uuid, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    IF v_safe ? 'task_list_id' AND NULLIF(v_safe->>'task_list_id', '') IS NOT NULL
       AND NOT public.can_add_task_to_list((v_safe->>'task_list_id')::uuid, auth.uid()) THEN
        RAISE EXCEPTION 'Task-list access denied' USING ERRCODE = '42501';
    END IF;
    v_next := jsonb_populate_record(v_task, v_safe);
    UPDATE public.tasks SET
        title = v_next.title, description = v_next.description, due_date = v_next.due_date,
        priority = v_next.priority, category = v_next.category, title_i18n = v_next.title_i18n,
        description_i18n = v_next.description_i18n, start_date = v_next.start_date,
        end_date = v_next.end_date, estimated_time = v_next.estimated_time,
        visibility = v_next.visibility, project_id = v_next.project_id, tags = v_next.tags,
        visible_to = v_next.visible_to, content_type = v_next.content_type,
        source_link = v_next.source_link, upload_link = v_next.upload_link,
        department = v_next.department, sub_type = v_next.sub_type, watchers = v_next.watchers,
        parent_task_id = v_next.parent_task_id, marketing_department = v_next.marketing_department,
        content_links = v_next.content_links, submission_links = v_next.submission_links,
        delivery_status = v_next.delivery_status, task_list_id = v_next.task_list_id,
        repeat_type = v_next.repeat_type, repeat_interval = v_next.repeat_interval,
        notify_via_email = v_next.notify_via_email, crm_deal_id = v_next.crm_deal_id,
        crm_workflow_kind = v_next.crm_workflow_kind
     WHERE id = p_task_id
     RETURNING to_jsonb(tasks) INTO v_result;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_task_secure(p_task_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_task public.tasks%ROWTYPE; v_can_delete boolean;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    SELECT task.* INTO v_task FROM public.tasks task WHERE task.id = p_task_id FOR UPDATE;
    IF NOT FOUND THEN RETURN false; END IF;
    SELECT (
        v_task.created_by = auth.uid()
        OR public.can_assign_tasks_company_wide(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.task_lists list
            WHERE list.id = v_task.task_list_id
              AND auth.uid() = ANY(COALESCE(list.can_delete_users, '{}'::uuid[]))
        )
    ) INTO v_can_delete;
    IF NOT v_can_delete THEN RAISE EXCEPTION 'You are not authorized to delete this task' USING ERRCODE = '42501'; END IF;
    DELETE FROM public.tasks WHERE id = p_task_id;
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.change_crm_deal_stage(
    p_deal_id uuid,
    p_new_stage text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_new_stage text := UPPER(BTRIM(COALESCE(p_new_stage, '')));
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to change CRM deals' USING ERRCODE = '42501';
    END IF;

    IF v_new_stage NOT IN ('LEAD', 'QUALIFICATION', 'PITCH', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST') THEN
        RAISE EXCEPTION 'Invalid CRM deal stage' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_deal
      FROM public.crm_deals
     WHERE id = p_deal_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002';
    END IF;

    IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' AND v_new_stage = 'LOST' THEN
        RAISE EXCEPTION 'Lost deals must be deliberately reopened before editing' USING ERRCODE = '42501';
    END IF;

    -- Presentation, Discussion and Won are workflow-controlled stages.  The
    -- dedicated approval/project RPCs are the only paths that may establish
    -- those states; a mobile client cannot bypass them with a PATCH request.
    IF v_new_stage = 'PITCH'
       AND COALESCE(v_deal.workflow_status, '') NOT IN (
           'PENDING_APPROVAL', 'APPROVED', 'DESIGN_IN_PROGRESS',
           'DESIGN_PENDING_APPROVAL', 'DESIGN_REJECTED'
       ) THEN
        RAISE EXCEPTION 'Start the Presentation approval workflow before entering this stage' USING ERRCODE = '42501';
    END IF;

    IF v_new_stage IN ('NEGOTIATION', 'WON')
       AND COALESCE(v_deal.workflow_status, '') <> 'APPROVED' THEN
        RAISE EXCEPTION 'Complete all required approvals before advancing this deal' USING ERRCODE = '42501';
    END IF;

    UPDATE public.crm_deals
       SET stage = v_new_stage,
           proposal_sent_at = CASE
               WHEN v_new_stage = 'PROPOSAL' AND proposal_sent_at IS NULL THEN now()
               ELSE proposal_sent_at
           END
     WHERE id = v_deal.id;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, actor_id)
    VALUES (v_deal.id, 'STAGE_CHANGED', v_deal.stage, v_new_stage, auth.uid());

    RETURN jsonb_build_object(
        'deal_id', v_deal.id,
        'from_stage', v_deal.stage,
        'to_stage', v_new_stage,
        'actor_id', auth.uid()
    );
END;
$$;

-- Keep the legacy approval modal on the same atomic server-side path as the
-- newer Presentation workflow.  The caller supplies the selected reviewers,
-- but never writes the deal stage directly.
CREATE OR REPLACE FUNCTION public.start_deal_approval(
    p_deal_id uuid,
    p_marketing_manager uuid,
    p_general_manager uuid,
    p_operations_manager uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to start CRM approval' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
    IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN
        RAISE EXCEPTION 'Lost deals must be deliberately reopened before starting approval' USING ERRCODE = '42501';
    END IF;
    IF p_marketing_manager IS NULL OR p_general_manager IS NULL OR p_operations_manager IS NULL THEN
        RAISE EXCEPTION 'All approval reviewers are required' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM UNNEST(ARRAY[p_marketing_manager, p_general_manager, p_operations_manager]) reviewer_id
         WHERE NOT EXISTS (
             SELECT 1 FROM public.profiles reviewer
              WHERE reviewer.id = reviewer_id AND reviewer.is_active IS DISTINCT FROM false
         )
    ) THEN
        RAISE EXCEPTION 'All approval reviewers must be active employees' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;
    INSERT INTO public.crm_deal_approval_steps (deal_id, step_order, stage_key, approver_id)
    VALUES
        (p_deal_id, 1, 'MARKETING_MANAGER', p_marketing_manager),
        (p_deal_id, 2, 'GENERAL_MANAGER', p_general_manager),
        (p_deal_id, 3, 'OPERATIONS_MANAGER', p_operations_manager);
    UPDATE public.crm_deals
       SET stage = 'PITCH', workflow_status = 'PENDING_APPROVAL',
           proposal_sent_at = COALESCE(proposal_sent_at, now())
     WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, actor_id)
    VALUES (p_deal_id, 'APPROVAL_STARTED', v_deal.stage, 'PITCH', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_crm_deal_approval(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_total integer;
    v_approved integer;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to finalize CRM approval' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
    SELECT count(*), count(*) FILTER (WHERE status = 'APPROVED')
      INTO v_total, v_approved
      FROM public.crm_deal_approval_steps
     WHERE deal_id = p_deal_id;
    IF v_total = 0 OR v_total <> v_approved THEN
        RAISE EXCEPTION 'All CRM approval steps must be approved first' USING ERRCODE = '42501';
    END IF;

    UPDATE public.crm_deals SET stage = 'NEGOTIATION', workflow_status = 'APPROVED' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, actor_id)
    VALUES (p_deal_id, 'STAGE_CHANGED', v_deal.stage, 'NEGOTIATION', auth.uid());
    RETURN jsonb_build_object('deal_id', p_deal_id, 'from_stage', v_deal.stage, 'to_stage', 'NEGOTIATION', 'actor_id', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_crm_deal_lost(
    p_deal_id uuid,
    p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_reason text := NULLIF(BTRIM(COALESCE(p_reason, '')), '');
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to update CRM deals' USING ERRCODE = '42501';
    END IF;
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'A reason for loss is required' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002';
    END IF;
    IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN
        RAISE EXCEPTION 'This deal is already lost' USING ERRCODE = '42501';
    END IF;

    UPDATE public.crm_deals
       SET stage = 'LOST', lost_reason = v_reason
     WHERE id = v_deal.id;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (v_deal.id, 'DEAL_LOST', v_deal.stage, 'LOST', v_reason, auth.uid());

    RETURN jsonb_build_object(
        'deal_id', v_deal.id,
        'from_stage', v_deal.stage,
        'to_stage', 'LOST',
        'reason', v_reason,
        'actor_id', auth.uid()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.change_task_status(
    p_task_id uuid,
    p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_status text := NULLIF(BTRIM(COALESCE(p_status, '')), '');
    v_can_manage boolean := false;
BEGIN
    IF auth.uid() IS NULL OR v_status IS NULL THEN
        RAISE EXCEPTION 'A task and status are required' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT EXISTS (
        SELECT 1
          FROM public.profiles profile
         WHERE profile.id = auth.uid()
           AND profile.is_active IS DISTINCT FROM false
           AND (
               profile.id IN (v_task.created_by, v_task.assignee_id, v_task.supervisor_id)
               OR auth.uid() = ANY(COALESCE(v_task.assignee_ids, '{}'::uuid[]))
               OR UPPER(COALESCE(profile.role, '')) IN ('ADMIN', 'MANAGER', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'CEO', 'GM', 'GENERAL MANAGER')
               OR UPPER(COALESCE(profile.job_title, '')) IN ('CEO', 'GM', 'GENERAL MANAGER')
           )
    ) INTO v_can_manage;

    IF NOT v_can_manage THEN
        RAISE EXCEPTION 'You are not authorized to change this task' USING ERRCODE = '42501';
    END IF;

    UPDATE public.tasks SET status = v_status WHERE id = v_task.id;

    RETURN jsonb_build_object(
        'task_id', v_task.id,
        'from_status', v_task.status,
        'to_status', v_status,
        'actor_id', auth.uid()
    );
END;
$$;

-- Assignment is a separate transition from editing task content.  Keep the
-- actor and assignee validation on the server so a native client cannot
-- assign a task by issuing an arbitrary PATCH request.
CREATE OR REPLACE FUNCTION public.assign_task(
    p_task_id uuid,
    p_assignee_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_ids uuid[];
    v_invalid uuid;
    v_can_assign boolean := false;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = auth.uid()
          AND profile.is_active IS DISTINCT FROM false
          AND (
              profile.id IN (v_task.created_by, v_task.supervisor_id)
              OR UPPER(COALESCE(profile.role, '')) IN ('ADMIN','OWNER','ROLE SYSTEM ADMIN','SYSTEM ADMIN','CEO','GM','GENERAL MANAGER')
              OR UPPER(COALESCE(profile.job_title, '')) IN ('CEO','GM','GENERAL MANAGER')
              OR COALESCE(public.can_assign_tasks_company_wide(auth.uid()), false)
          )
    ) INTO v_can_assign;
    IF NOT v_can_assign THEN
        RAISE EXCEPTION 'You are not authorized to assign this task' USING ERRCODE = '42501';
    END IF;

    SELECT ARRAY_AGG(DISTINCT value) INTO v_ids
      FROM UNNEST(COALESCE(p_assignee_ids, ARRAY[]::uuid[])) value
     WHERE value IS NOT NULL;
    SELECT value INTO v_invalid
      FROM UNNEST(COALESCE(v_ids, ARRAY[]::uuid[])) value
     WHERE NOT EXISTS (
         SELECT 1 FROM public.profiles profile
          WHERE profile.id = value AND profile.is_active IS DISTINCT FROM false
     )
     LIMIT 1;
    IF v_invalid IS NOT NULL THEN
        RAISE EXCEPTION 'Every assignee must be an active employee' USING ERRCODE = '22023';
    END IF;

    UPDATE public.tasks
       SET assignee_ids = COALESCE(v_ids, ARRAY[]::uuid[]),
           assignee_id = (COALESCE(v_ids, ARRAY[]::uuid[]))[1]
     WHERE id = v_task.id;

    RETURN jsonb_build_object(
        'task_id', v_task.id,
        'assignee_ids', COALESCE(v_ids, ARRAY[]::uuid[]),
        'actor_id', auth.uid()
    );
END;
$$;

-- Narrow, server-authoritative project transitions used by both web and
-- future mobile adapters.  Team assignment is deliberately separate from
-- general project editing so the permission boundary is explicit.
CREATE OR REPLACE FUNCTION public.change_project_status(
    p_project_id uuid,
    p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_status text := UPPER(BTRIM(COALESCE(p_status, '')));
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    IF NOT public.is_project_portfolio_admin(auth.uid()) THEN
        SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
        IF NOT FOUND OR (v_project.created_by <> auth.uid() AND v_project.project_manager_id <> auth.uid()) THEN
            RAISE EXCEPTION 'Only the project owner or manager can change project status' USING ERRCODE = '42501';
        END IF;
    ELSE
        SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
    END IF;
    IF v_status NOT IN ('PLANNING','ACTIVE','ON_HOLD','COMPLETED','CANCELLED') THEN
        RAISE EXCEPTION 'Invalid project status' USING ERRCODE = '22023';
    END IF;

    UPDATE public.projects
       SET lifecycle_status = v_status,
           project_status = CASE v_status
               WHEN 'PLANNING' THEN 'Planning'
               WHEN 'ACTIVE' THEN 'In Progress'
               WHEN 'ON_HOLD' THEN 'On Hold'
               WHEN 'COMPLETED' THEN 'Completed'
               WHEN 'CANCELLED' THEN 'Cancelled'
           END,
           updated_at = NOW()
     WHERE id = p_project_id;

    IF to_regclass('public.project_updates') IS NOT NULL THEN
        INSERT INTO public.project_updates(project_id, author_id, update_type, summary)
        VALUES (p_project_id, auth.uid(), 'UPDATE', format('Project status changed to %s', v_status));
    END IF;
    RETURN jsonb_build_object('project_id', p_project_id, 'status', v_status, 'actor_id', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_project_team(
    p_project_id uuid,
    p_project_manager_id uuid,
    p_assignee_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_ids uuid[];
    v_invalid uuid;
    v_can_manage boolean := false;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE = 'P0002'; END IF;
    SELECT public.is_project_portfolio_admin(auth.uid())
        OR v_project.created_by = auth.uid()
        OR v_project.project_manager_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.profiles profile
             WHERE profile.id = auth.uid()
               AND profile.is_active IS DISTINCT FROM false
               AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) IN ('OPERATIONS MANAGER','OPERATION MANAGER','PROJECT MANAGER')
        ) INTO v_can_manage;
    IF NOT v_can_manage THEN RAISE EXCEPTION 'Only a project manager can assign the project team' USING ERRCODE = '42501'; END IF;

    SELECT ARRAY_AGG(DISTINCT value) INTO v_ids
      FROM UNNEST(COALESCE(p_assignee_ids, ARRAY[]::uuid[])) value
     WHERE value IS NOT NULL;
    SELECT value INTO v_invalid
      FROM UNNEST(COALESCE(v_ids, ARRAY[]::uuid[])) value
     WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile WHERE profile.id = value AND profile.is_active IS DISTINCT FROM false)
     LIMIT 1;
    IF v_invalid IS NOT NULL THEN RAISE EXCEPTION 'Every project assignee must be active' USING ERRCODE = '22023'; END IF;
    IF p_project_manager_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.profiles profile WHERE profile.id = p_project_manager_id AND profile.is_active IS DISTINCT FROM false
    ) THEN RAISE EXCEPTION 'Project manager must be an active employee' USING ERRCODE = '22023'; END IF;

    UPDATE public.projects
       SET project_manager_id = p_project_manager_id,
           assigned_people = COALESCE(v_ids, ARRAY[]::uuid[]),
           updated_at = NOW()
     WHERE id = p_project_id;
    RETURN jsonb_build_object('project_id', p_project_id, 'project_manager_id', p_project_manager_id,
                              'assigned_people', COALESCE(v_ids, ARRAY[]::uuid[]), 'actor_id', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.create_project_update_secure(
    p_project_id uuid,
    p_summary text,
    p_update_type text DEFAULT 'UPDATE'
)
RETURNS public.project_updates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_update public.project_updates%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    IF NULLIF(BTRIM(p_summary), '') IS NULL THEN RAISE EXCEPTION 'Project update is required' USING ERRCODE = '22023'; END IF;
    INSERT INTO public.project_updates(project_id, author_id, update_type, summary)
    VALUES (p_project_id, auth.uid(), UPPER(COALESCE(p_update_type, 'UPDATE')), BTRIM(p_summary))
    RETURNING * INTO v_update;
    RETURN v_update;
END;
$$;

REVOKE ALL ON FUNCTION public.change_crm_deal_stage(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_crm_deal_lost(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.change_task_status(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_task(uuid, uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.change_project_status(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_project_team(uuid, uuid, uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_project_update_secure(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.start_deal_approval(uuid, uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finalize_crm_deal_approval(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_crm_deal_stage(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_crm_deal_lost(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_task_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_task(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_project_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_project_team(uuid, uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_project_update_secure(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_deal_approval(uuid, uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_crm_deal_approval(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
