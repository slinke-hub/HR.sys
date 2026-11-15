-- Extend the existing read-only archived-task exception to managers and
-- supervisors, while allowing employees to open tasks they completed.
-- Archived rows remain protected from all normal mutations.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_view_archived_task(p_task_id uuid)
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
      AND task.archived_at IS NOT NULL
      AND auth.uid() IS NOT NULL
      AND (
        EXISTS (
          SELECT 1
          FROM public.profiles viewer
          WHERE viewer.id = auth.uid()
            AND viewer.is_active IS DISTINCT FROM FALSE
            AND (
              public.can_assign_tasks_company_wide(auth.uid())
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) IN ('MANAGER', 'SUPERVISOR')
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.job_title, ''), '[_-]+', ' ', 'g'))) ~ '(^|[^A-Z])(MANAGER|SUPERVISOR)([^A-Z]|$)'
              OR COALESCE(viewer.job_title_ar, '') ~ '(مدير|مشرف)'
            )
        )
        OR task.created_by = auth.uid()
        OR task.assignee_id = auth.uid()
        OR auth.uid() = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
        OR auth.uid() = ANY(COALESCE(task.watchers, '{}'::uuid[]))
        OR EXISTS (
          SELECT 1
          FROM public.task_activity activity
          WHERE activity.task_id = task.id
            AND activity.actor_id = auth.uid()
            AND (
              activity.action = 'TASK_COMPLETED'
              OR LOWER(COALESCE(activity.to_status, '')) = 'completed'
            )
        )
      )
  );
$$;

REVOKE ALL ON FUNCTION public.can_view_archived_task(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_archived_task(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
