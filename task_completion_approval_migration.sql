-- Require department-manager approval before any task can move to Done.
-- Run in the Supabase SQL Editor after tasks_teamwork_workflow_migration.sql.
BEGIN;

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS completion_requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completion_requested_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS completion_approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS completion_approved_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.is_task_department_manager(p_department TEXT, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.departments department
        WHERE department.name = p_department AND department.head_id = p_user_id
    );
$$;

CREATE OR REPLACE FUNCTION public.enforce_task_completion_approval()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
        IF public.is_task_department_manager(NEW.department, auth.uid()) THEN
            NEW.completion_approved_by := auth.uid();
            NEW.completion_approved_at := now();
        ELSE
            NEW.status := 'Pending Approval';
            NEW.completion_requested_by := auth.uid();
            NEW.completion_requested_at := now();
            NEW.completion_approved_by := NULL;
            NEW.completion_approved_at := NULL;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_task_completion_approval_trigger ON public.tasks;
CREATE TRIGGER enforce_task_completion_approval_trigger
    BEFORE INSERT OR UPDATE OF status ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.enforce_task_completion_approval();

-- Designing tasks keep their special Delivery Status control, but completion
-- attempts now flow through the universal approval trigger.
CREATE OR REPLACE FUNCTION public.enforce_marketing_design_review()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE is_designing BOOLEAN;
BEGIN
    is_designing := NEW.department = 'Marketing' AND NEW.sub_type = 'Designing Task';
    IF NOT is_designing THEN RETURN NEW; END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.delivery_status IS NOT NULL AND NOT public.is_marketing_department_manager(auth.uid()) THEN
            RAISE EXCEPTION 'Only the Marketing department manager can set Delivery Status' USING ERRCODE = '42501';
        END IF;
        NEW.status := CASE WHEN NEW.delivery_status = 'Approved' THEN 'completed' ELSE 'review' END;
        RETURN NEW;
    END IF;
    IF NEW.delivery_status IS DISTINCT FROM OLD.delivery_status
       AND NOT public.is_marketing_department_manager(auth.uid()) THEN
        RAISE EXCEPTION 'Only the Marketing department manager can change Delivery Status' USING ERRCODE = '42501';
    END IF;
    IF NEW.delivery_status IS DISTINCT FROM OLD.delivery_status THEN
        NEW.status := CASE WHEN NEW.delivery_status = 'Approved' THEN 'completed' ELSE 'review' END;
    END IF;
    RETURN NEW;
END;
$$;

-- Include the selected department manager in every task notification.
CREATE OR REPLACE FUNCTION public.queue_task_notification(p_task_id UUID, p_actor_id UUID, p_event_type TEXT, p_message TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE task_row public.tasks%ROWTYPE; recipient UUID; notification_row public.notifications%ROWTYPE; manager_id UUID;
BEGIN
    SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id;
    IF NOT FOUND THEN RETURN; END IF;
    SELECT head_id INTO manager_id FROM public.departments WHERE name = task_row.department LIMIT 1;
    FOR recipient IN
        SELECT DISTINCT recipient_id FROM (
            SELECT unnest(array_remove(ARRAY[task_row.created_by, task_row.assignee_id, task_row.supervisor_id, manager_id], NULL)) recipient_id
            UNION SELECT unnest(COALESCE(task_row.watchers, '{}'))
            UNION SELECT unnest(COALESCE(task_row.visible_to, '{}'))
            UNION SELECT unnest(COALESCE(project.assigned_people, '{}')) FROM public.projects project WHERE project.id = task_row.project_id
            UNION SELECT user_id FROM public.task_comments WHERE task_id = p_task_id
        ) recipients WHERE recipient_id IS DISTINCT FROM p_actor_id
    LOOP
        INSERT INTO public.notifications(user_id,message,event_type,task_id,actor_id,action_url,metadata)
        VALUES(recipient,p_message,p_event_type,p_task_id,p_actor_id,'/tasks-v2?task='||p_task_id,
            jsonb_build_object('task_title',task_row.title,'parent_task_id',task_row.parent_task_id,'department_manager_id',manager_id))
        RETURNING * INTO notification_row;
        BEGIN
            INSERT INTO public.task_email_outbox(notification_id,recipient_id,recipient_email,subject,message,action_url)
            SELECT notification_row.id,profile.id,auth_user.email,
                CASE WHEN p_event_type='task_comment' THEN 'New comment: ' WHEN p_event_type='task_approval_requested' THEN 'Approval required: ' ELSE 'Task update: ' END||task_row.title,
                p_message,notification_row.action_url
            FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id=profile.id
            WHERE profile.id=recipient AND profile.task_email_notifications=TRUE AND NULLIF(BTRIM(auth_user.email),'') IS NOT NULL;
        EXCEPTION WHEN OTHERS THEN RAISE WARNING 'Unable to queue task email: %',SQLERRM; END;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_task_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        PERFORM public.queue_task_notification(NEW.id,NEW.created_by,CASE WHEN NEW.parent_task_id IS NULL THEN 'task_created' ELSE 'subtask_created' END,CASE WHEN NEW.parent_task_id IS NULL THEN 'New task: ' ELSE 'New subtask: ' END||NEW.title);
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        PERFORM public.queue_task_notification(NEW.id,auth.uid(),CASE WHEN NEW.status='Pending Approval' THEN 'task_approval_requested' ELSE 'task_status_changed' END,
            CASE WHEN NEW.status='Pending Approval' THEN 'Completion approval requested for "'||NEW.title||'"' ELSE 'Task "'||NEW.title||'" changed from '||OLD.status||' to '||NEW.status END);
    ELSIF NEW.assignee_id IS DISTINCT FROM OLD.assignee_id THEN
        PERFORM public.queue_task_notification(NEW.id,auth.uid(),'task_assigned','Task assigned: '||NEW.title);
    ELSE
        PERFORM public.queue_task_notification(NEW.id,auth.uid(),'task_updated','Task updated: '||NEW.title);
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.is_task_department_manager(TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_task_department_manager(TEXT,UUID) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
