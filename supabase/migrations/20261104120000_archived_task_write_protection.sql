-- Keep archived task history read-only across SECURITY DEFINER write paths.
-- These guards are database-side so privileged RPCs cannot bypass them.
BEGIN;

CREATE OR REPLACE FUNCTION public.guard_archived_task_row_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor uuid := auth.uid();
BEGIN
    -- Trusted service maintenance and direct postgres DBA operations remain
    -- available. The scheduled archive job only touches currently active rows.
    IF auth.role() = 'service_role' OR session_user IN ('postgres', 'service_role') THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF OLD.archived_at IS NULL THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    -- Preserve a narrow admin restore operation, if invoked through an
    -- authorized server path: clear only archived_at (and timestamp metadata).
    IF TG_OP = 'UPDATE' THEN
        IF NEW.archived_at IS NULL
           AND v_actor IS NOT NULL
           AND public.can_assign_tasks_company_wide(v_actor)
           AND (to_jsonb(NEW) - 'archived_at' - 'updated_at')
               = (to_jsonb(OLD) - 'archived_at' - 'updated_at') THEN
            RETURN NEW;
        END IF;
    END IF;

    RAISE EXCEPTION 'Archived tasks are read-only' USING ERRCODE = '42501';
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_archived_task_child_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_old jsonb := CASE WHEN TG_OP = 'INSERT' THEN '{}'::jsonb ELSE to_jsonb(OLD) END;
    v_new jsonb := CASE WHEN TG_OP = 'DELETE' THEN '{}'::jsonb ELSE to_jsonb(NEW) END;
    v_parent_ids uuid[] := ARRAY[]::uuid[];
    v_parent_id uuid;
    v_archived_at timestamptz;
BEGIN
    IF auth.role() = 'service_role' OR session_user IN ('postgres', 'service_role') THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'task_dependencies' THEN
        v_parent_ids := ARRAY[
            NULLIF(v_old->>'predecessor_task_id', '')::uuid,
            NULLIF(v_old->>'successor_task_id', '')::uuid,
            NULLIF(v_new->>'predecessor_task_id', '')::uuid,
            NULLIF(v_new->>'successor_task_id', '')::uuid
        ];
    ELSE
        v_parent_ids := ARRAY[
            NULLIF(v_old->>'task_id', '')::uuid,
            NULLIF(v_new->>'task_id', '')::uuid
        ];
    END IF;

    IF TG_OP = 'DELETE' AND EXISTS (
        SELECT 1
        FROM unnest(v_parent_ids) AS ids(id)
        WHERE ids.id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM public.tasks task WHERE task.id = ids.id)
    ) THEN
        -- Parent deletion cleanup is independent of any other surviving
        -- endpoint's archive state; no archived parent row is being changed.
        RETURN OLD;
    END IF;

    -- Lock parents in stable order so a concurrent archive cannot race a
    -- child write and dependency edits do not deadlock across endpoint order.
    FOR v_parent_id IN
        SELECT DISTINCT ids.id
        FROM unnest(v_parent_ids) AS ids(id)
        WHERE ids.id IS NOT NULL
        ORDER BY ids.id
    LOOP
        SELECT task.archived_at
          INTO v_archived_at
          FROM public.tasks task
         WHERE task.id = v_parent_id
         FOR UPDATE;

        IF NOT FOUND THEN
            -- Existing task-delete cleanup removes orphaned child rows after
            -- the parent is gone. Preserve that cleanup path only for DELETE;
            -- for dependencies, a missing endpoint means the row is being
            -- purged with its deleted task.
            IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
            RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002';
        END IF;

        IF v_archived_at IS NOT NULL THEN
            RAISE EXCEPTION 'Archived task records are read-only' USING ERRCODE = '42501';
        END IF;
    END LOOP;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_archived_task_row_write() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_archived_task_child_write() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS archived_task_row_write_guard ON public.tasks;
CREATE TRIGGER archived_task_row_write_guard
BEFORE UPDATE OR DELETE ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.guard_archived_task_row_write();

DROP TRIGGER IF EXISTS archived_task_comments_write_guard ON public.task_comments;
CREATE TRIGGER archived_task_comments_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.task_comments
FOR EACH ROW EXECUTE FUNCTION public.guard_archived_task_child_write();

DROP TRIGGER IF EXISTS archived_task_attachments_write_guard ON public.task_attachments;
CREATE TRIGGER archived_task_attachments_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.task_attachments
FOR EACH ROW EXECUTE FUNCTION public.guard_archived_task_child_write();

DROP TRIGGER IF EXISTS archived_task_activity_write_guard ON public.task_activity;
CREATE TRIGGER archived_task_activity_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.task_activity
FOR EACH ROW EXECUTE FUNCTION public.guard_archived_task_child_write();

DROP TRIGGER IF EXISTS archived_task_dependencies_write_guard ON public.task_dependencies;
CREATE TRIGGER archived_task_dependencies_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.task_dependencies
FOR EACH ROW EXECUTE FUNCTION public.guard_archived_task_child_write();

DROP TRIGGER IF EXISTS archived_task_waiting_history_write_guard ON public.task_waiting_history;
CREATE TRIGGER archived_task_waiting_history_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.task_waiting_history
FOR EACH ROW EXECUTE FUNCTION public.guard_archived_task_child_write();

DROP TRIGGER IF EXISTS archived_task_blocker_history_write_guard ON public.task_blocker_history;
CREATE TRIGGER archived_task_blocker_history_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.task_blocker_history
FOR EACH ROW EXECUTE FUNCTION public.guard_archived_task_child_write();

-- Storage object metadata has its own RLS boundary. Keep the existing
-- uploader/manager policies, and add a restrictive parent-active condition so
-- a fresh upload or object mutation cannot target an archived task.
DROP POLICY IF EXISTS task_attachment_storage_active_parent_insert ON storage.objects;
CREATE POLICY task_attachment_storage_active_parent_insert
ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (
    CASE
        WHEN bucket_id <> 'task-attachments' THEN TRUE
        WHEN COALESCE((storage.foldername(name))[1], '') ~* '^[0-9a-f-]{36}$'
        THEN auth.uid() IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.tasks task
            WHERE task.id = ((storage.foldername(name))[1])::uuid
              AND task.archived_at IS NULL
              AND public.can_manage_task_attachments(task.id, auth.uid())
        )
        ELSE FALSE
    END
);

DROP POLICY IF EXISTS task_attachment_storage_active_parent_update ON storage.objects;
CREATE POLICY task_attachment_storage_active_parent_update
ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
USING (
    CASE
        WHEN bucket_id <> 'task-attachments' THEN TRUE
        WHEN COALESCE((storage.foldername(name))[1], '') ~* '^[0-9a-f-]{36}$'
        THEN auth.uid() IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.tasks task
            WHERE task.id = ((storage.foldername(name))[1])::uuid
              AND task.archived_at IS NULL
              AND public.can_manage_task_attachments(task.id, auth.uid())
        )
        ELSE FALSE
    END
)
WITH CHECK (
    CASE
        WHEN bucket_id <> 'task-attachments' THEN TRUE
        WHEN COALESCE((storage.foldername(name))[1], '') ~* '^[0-9a-f-]{36}$'
        THEN auth.uid() IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.tasks task
            WHERE task.id = ((storage.foldername(name))[1])::uuid
              AND task.archived_at IS NULL
              AND public.can_manage_task_attachments(task.id, auth.uid())
        )
        ELSE FALSE
    END
);

DROP POLICY IF EXISTS task_attachment_storage_active_parent_delete ON storage.objects;
CREATE POLICY task_attachment_storage_active_parent_delete
ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
USING (
    CASE
        WHEN bucket_id <> 'task-attachments' THEN TRUE
        WHEN COALESCE((storage.foldername(name))[1], '') ~* '^[0-9a-f-]{36}$'
        THEN auth.uid() IS NOT NULL AND EXISTS (
            SELECT 1 FROM public.tasks task
            WHERE task.id = ((storage.foldername(name))[1])::uuid
              AND task.archived_at IS NULL
              AND public.can_manage_task_attachments(task.id, auth.uid())
        )
        ELSE FALSE
    END
);

-- The scheduled job is installed by 20260905230500 and runs as the trusted
-- database maintenance role. Undo any later broad grants without changing it.
REVOKE ALL ON FUNCTION public.archive_completed_tasks() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.archive_completed_tasks() TO service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
