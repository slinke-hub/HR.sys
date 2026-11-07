-- Let employees read archived tasks they own or were explicitly selected to watch.
-- This is a read-only archive exception; can_access_task and write RPC checks
-- remain unchanged. Existing restrictive policies (including MQ-20) still apply.
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
        task.created_by = auth.uid()
        OR task.assignee_id = auth.uid()
        OR auth.uid() = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
        OR auth.uid() = ANY(COALESCE(task.watchers, '{}'::uuid[]))
      )
  );
$$;

REVOKE ALL ON FUNCTION public.can_view_archived_task(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_archived_task(uuid) TO authenticated;

-- Keep the restrictive task boundary in place. The extra branch is limited to
-- archived rows and the authenticated caller's own assignment/creator/watcher IDs.
DROP POLICY IF EXISTS task_secure_access_select ON public.tasks;
CREATE POLICY task_secure_access_select ON public.tasks AS RESTRICTIVE
  FOR SELECT TO authenticated
  USING (
    public.can_access_task(id, auth.uid())
    OR public.can_view_archived_task(id)
  );

-- A restrictive policy can only narrow access. This permissive branch supplies SELECT for the helper's narrowly authorized archived rows; every existing restrictive policy (including MQ-20) still applies.
CREATE POLICY task_archived_self_read ON public.tasks AS PERMISSIVE
  FOR SELECT TO authenticated
  USING (public.can_view_archived_task(id));

-- Archived watcher access is read-only. The existing write RPCs continue to
-- require can_access_task/can_manage_task and therefore do not inherit this grant.
CREATE OR REPLACE FUNCTION public.list_task_comments_secure(p_task_id uuid)
RETURNS SETOF public.task_comments
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT *
  FROM public.task_comments
  WHERE task_id = p_task_id
    AND auth.uid() IS NOT NULL
    AND (
      public.can_access_task(p_task_id, auth.uid())
      OR public.can_view_archived_task(p_task_id)
    )
  ORDER BY created_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.list_task_attachments_secure(
  p_task_id uuid,
  p_scope text DEFAULT NULL
)
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'id', id,
    'task_id', task_id,
    'file_url', file_url,
    'storage_reference', file_url,
    'file_name', file_name,
    'file_type', file_type,
    'file_size', file_size,
    'attachment_scope', attachment_scope,
    'visible_to_project_assignee', visible_to_project_assignee,
    'created_at', created_at
  )
  FROM public.task_attachments
  WHERE task_id = p_task_id
    AND is_archived = false
    AND (p_scope IS NULL OR attachment_scope = UPPER(p_scope))
    AND auth.uid() IS NOT NULL
    AND (
      public.can_access_task(p_task_id, auth.uid())
      OR public.can_view_archived_task(p_task_id)
    )
  ORDER BY created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.list_task_activity_secure(p_task_id uuid)
RETURNS SETOF public.task_activity
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT *
  FROM public.task_activity
  WHERE task_id = p_task_id
    AND auth.uid() IS NOT NULL
    AND (
      public.can_access_task(p_task_id, auth.uid())
      OR public.can_view_archived_task(p_task_id)
    )
  ORDER BY created_at DESC;
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
