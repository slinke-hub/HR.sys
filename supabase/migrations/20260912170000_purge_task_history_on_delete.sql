-- Migration: Complete task history and attachment cleanup upon task deletion
-- Ensures no orphaned records, comments, notifications, outbox entries, or attachments linger when a task is deleted.

BEGIN;

CREATE OR REPLACE FUNCTION public.clean_task_history_on_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- 1. Remove related task attachments from task_attachments table
    IF to_regclass('public.task_attachments') IS NOT NULL THEN
        DELETE FROM public.task_attachments WHERE task_id = OLD.id;
    END IF;

    -- 2. Remove related task comments from task_comments table
    IF to_regclass('public.task_comments') IS NOT NULL THEN
        DELETE FROM public.task_comments WHERE task_id = OLD.id;
    END IF;

    -- 3. Remove queued or sent emails for this task from task_email_outbox
    IF to_regclass('public.task_email_outbox') IS NOT NULL THEN
        DELETE FROM public.task_email_outbox WHERE task_id = OLD.id;
    END IF;

    -- 4. Remove notifications linked to this task id or mentioning this task title
    IF to_regclass('public.notifications') IS NOT NULL THEN
        DELETE FROM public.notifications
        WHERE task_id = OLD.id
           OR (metadata->>'task_title' IS NOT NULL AND metadata->>'task_title' = OLD.title)
           OR action_url LIKE '%task=' || OLD.id::text || '%';
    END IF;

    -- 5. Clean up CRM design task approval steps if table exists
    IF to_regclass('public.crm_design_task_approval_steps') IS NOT NULL THEN
        DELETE FROM public.crm_design_task_approval_steps WHERE task_id = OLD.id;
    END IF;

    -- 6. Unlink from CRM deals if referenced
    IF to_regclass('public.crm_deals') IS NOT NULL THEN
        UPDATE public.crm_deals
        SET design_task_id = NULL
        WHERE design_task_id = OLD.id;
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_clean_task_history_on_delete ON public.tasks;
CREATE TRIGGER trg_clean_task_history_on_delete
    BEFORE DELETE ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.clean_task_history_on_delete();

COMMIT;
