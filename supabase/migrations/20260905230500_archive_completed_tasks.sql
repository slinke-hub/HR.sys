-- Keep completed task history in the tasks table so comments, attachments,
-- recurrence metadata, and audit relationships remain intact.
ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS archived_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_tasks_archived_at
    ON public.tasks (archived_at DESC)
    WHERE archived_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.archive_completed_tasks()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    archived_count integer;
BEGIN
    UPDATE public.tasks
       SET archived_at = now()
     WHERE archived_at IS NULL
       AND lower(btrim(coalesce(status, ''))) IN ('completed', 'approved');

    GET DIAGNOSTICS archived_count = ROW_COUNT;
    RETURN archived_count;
END;
$$;

REVOKE ALL ON FUNCTION public.archive_completed_tasks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.archive_completed_tasks() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.archive_completed_tasks() TO service_role;

CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
DECLARE
    existing_job_id bigint;
BEGIN
    SELECT jobid
      INTO existing_job_id
      FROM cron.job
     WHERE jobname = 'archive-completed-tasks-after-11pm'
     LIMIT 1;

    IF existing_job_id IS NOT NULL THEN
        PERFORM cron.unschedule(existing_job_id);
    END IF;

    -- Supabase cron uses UTC. 20:05 UTC is 23:05 in Riyadh (UTC+3).
    PERFORM cron.schedule(
        'archive-completed-tasks-after-11pm',
        '5 20 * * *',
        'SELECT public.archive_completed_tasks();'
    );
END;
$$;

-- Put any tasks already completed before this migration into the archive now.
SELECT public.archive_completed_tasks();

NOTIFY pgrst, 'reload schema';
