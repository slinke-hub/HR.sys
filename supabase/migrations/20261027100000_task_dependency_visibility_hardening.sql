-- Keep dependency metadata within the caller's effective visibility boundary.
-- This is forward-only and preserves dependency/activity rows and RPC signatures.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_view_task_dependency(
  p_predecessor_task_id uuid,
  p_successor_task_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND p_user_id = auth.uid()
    AND public.can_access_task(p_predecessor_task_id, p_user_id)
    AND public.can_access_task(p_successor_task_id, p_user_id);
$$;
REVOKE ALL ON FUNCTION public.can_view_task_dependency(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_task_dependency(uuid, uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.task_dependency_blocked_visible(
  p_task_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND p_user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.task_dependencies dependency
      JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
      WHERE dependency.successor_task_id = p_task_id
        AND dependency.removed_at IS NULL
        AND predecessor.status <> 'completed'
        AND public.can_view_task_dependency(
          dependency.predecessor_task_id, dependency.successor_task_id, p_user_id
        )
    );
$$;
REVOKE ALL ON FUNCTION public.task_dependency_blocked_visible(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.task_activity_dependency_visible(
  p_task_id uuid,
  p_action text,
  p_metadata jsonb,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p_user_id IS NOT NULL
    AND p_user_id = auth.uid()
    AND public.can_access_task(p_task_id, p_user_id)
    AND (
      (
        p_action NOT LIKE 'TASK_DEPENDENCY%'
        AND p_action <> 'TASK_HANDOFF'
      )
      OR (
        p_action LIKE 'TASK_DEPENDENCY%'
        AND EXISTS (
        SELECT 1
        FROM public.tasks other_task
        WHERE other_task.id::text = COALESCE(
          NULLIF(p_metadata->>'predecessor_task_id', p_task_id::text),
          NULLIF(p_metadata->>'successor_task_id', p_task_id::text)
        )
          AND public.can_access_task(other_task.id, p_user_id)
        )
      )
      OR (
        p_action = 'TASK_HANDOFF'
        AND jsonb_typeof(p_metadata->'successor_task_ids') = 'array'
        AND NOT EXISTS (
          SELECT 1
          FROM jsonb_array_elements_text(
            CASE WHEN jsonb_typeof(p_metadata->'successor_task_ids') = 'array'
              THEN p_metadata->'successor_task_ids' ELSE '[]'::jsonb END
          ) endpoint(value)
          WHERE NOT EXISTS (
            SELECT 1 FROM public.tasks other_task
            WHERE other_task.id::text = endpoint.value
              AND public.can_access_task(other_task.id, p_user_id)
          )
        )
      )
    );
$$;
REVOKE ALL ON FUNCTION public.task_activity_dependency_visible(uuid, text, jsonb, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.task_activity_dependency_visible(uuid, text, jsonb, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_task_dependencies_secure(p_task_id uuid)
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'dependency_id', dependency.id,
    'predecessor_task_id', dependency.predecessor_task_id,
    'successor_task_id', dependency.successor_task_id,
    'relationship', CASE WHEN dependency.successor_task_id = p_task_id THEN 'depends_on' ELSE 'unlocks' END,
    'is_satisfied', predecessor.status = 'completed',
    'is_blocking', predecessor.status <> 'completed',
    'created_at', dependency.created_at,
    'predecessor', jsonb_build_object(
      'id', predecessor.id, 'title', predecessor.title, 'title_i18n', predecessor.title_i18n,
      'status', predecessor.status, 'due_date', predecessor.due_date,
      'assignee_id', predecessor.assignee_id
    ),
    'successor', jsonb_build_object(
      'id', successor.id, 'title', successor.title, 'title_i18n', successor.title_i18n,
      'status', successor.status, 'due_date', successor.due_date,
      'assignee_id', successor.assignee_id
    )
  )
  FROM public.task_dependencies dependency
  JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
  JOIN public.tasks successor ON successor.id = dependency.successor_task_id
  WHERE dependency.removed_at IS NULL
    AND (dependency.predecessor_task_id = p_task_id OR dependency.successor_task_id = p_task_id)
    AND auth.uid() IS NOT NULL
    AND public.can_view_task_dependency(predecessor.id, successor.id, auth.uid())
  ORDER BY dependency.created_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.list_task_dependency_history_secure(p_task_id uuid)
RETURNS SETOF public.task_activity
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT activity.*
  FROM public.task_activity activity
  WHERE activity.task_id = p_task_id
    AND activity.action IN (
      'TASK_DEPENDENCY_CREATED', 'TASK_DEPENDENCY_REMOVED',
      'TASK_DEPENDENCY_BLOCKED', 'TASK_DEPENDENCY_PREDECESSOR_COMPLETED',
      'TASK_DEPENDENCY_READY', 'TASK_HANDOFF', 'TASK_HANDOFF_NOTIFIED'
    )
    AND auth.uid() IS NOT NULL
    AND public.task_activity_dependency_visible(
      activity.task_id, activity.action, activity.metadata, auth.uid()
    )
  ORDER BY activity.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.list_task_dependency_blockers_secure()
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'task_id', successor.id,
    'title', successor.title,
    'title_i18n', successor.title_i18n,
    'status', successor.status,
    'assignee_id', successor.assignee_id,
    'due_date', successor.due_date,
    'project_id', successor.project_id,
    'project_name', project.project_name,
    'blocking_task_id', predecessor.id,
    'blocking_task_title', predecessor.title,
    'blocking_task_title_i18n', predecessor.title_i18n,
    'blocking_employee_id', predecessor.assignee_id,
    'waiting_since', dependency.created_at
  )
  FROM public.task_dependencies dependency
  JOIN public.tasks successor ON successor.id = dependency.successor_task_id
  JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
  LEFT JOIN public.projects project ON project.id = successor.project_id
  JOIN public.profiles viewer ON viewer.id = auth.uid()
  WHERE dependency.removed_at IS NULL
    AND predecessor.status <> 'completed'
    AND successor.status <> 'completed'
    AND viewer.is_active IS DISTINCT FROM false
    AND UPPER(COALESCE(viewer.role, '')) IN ('ADMIN','MANAGER','SUPERVISOR','CEO','GM','GENERAL MANAGER')
    AND public.can_view_task_dependency(predecessor.id, successor.id, auth.uid())
  ORDER BY dependency.created_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.complete_task_productivity(p_task_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  task_row public.tasks%ROWTYPE;
  changed boolean;
  activated jsonb := '[]'::jsonb;
  visible_successors jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_execute_task(p_task_id, auth.uid()) THEN
    RAISE EXCEPTION 'Task access denied' USING ERRCODE = '42501';
  END IF;
  IF public.task_dependency_blocked(p_task_id) THEN
    RAISE EXCEPTION 'Task is waiting for a previous task to complete' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
  changed := task_row.status <> 'completed';
  UPDATE public.tasks
  SET status = 'completed',
      completed_at = COALESCE(completed_at, now()),
      work_state = 'ACTIVE',
      waiting_category = NULL,
      waiting_related_user_id = NULL,
      waiting_note = NULL,
      waiting_since = NULL,
      blocked_category = NULL,
      blocked_related_user_id = NULL,
      blocked_note = NULL,
      blocked_since = NULL,
      resume_status = NULL
  WHERE id = p_task_id;
  IF changed THEN
    INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
    VALUES (p_task_id, auth.uid(), 'TASK_COMPLETED', '{}'::jsonb);
  END IF;
  SELECT COALESCE(public.activate_task_successors(p_task_id, auth.uid()), '[]'::jsonb)
  INTO activated;
  SELECT COALESCE(jsonb_agg(candidate.value), '[]'::jsonb)
  INTO visible_successors
  FROM jsonb_array_elements(activated) candidate(value)
  JOIN public.tasks successor ON successor.id::text = candidate.value #>> '{}'
  WHERE public.can_access_task(successor.id, auth.uid());
  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'status', 'completed',
    'completed_at', (SELECT completed_at FROM public.tasks WHERE id = p_task_id),
    'actor_id', auth.uid(),
    'changed', changed,
    'activated_successors', visible_successors
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_and_hand_off_task(
  p_task_id uuid,
  p_next_assignee_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  completion jsonb;
  successor_ids jsonb;
BEGIN
  IF p_next_assignee_id IS NOT NULL THEN
    RAISE EXCEPTION 'Free-form handoff is not available; use an authorized successor task assignment' USING ERRCODE = '42501';
  END IF;
  completion := public.complete_task_productivity(p_task_id);
  successor_ids := COALESCE(completion->'activated_successors', '[]'::jsonb);
  INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
  VALUES (
    p_task_id,
    auth.uid(),
    'TASK_HANDOFF',
    jsonb_build_object('successor_task_ids', successor_ids, 'dependency_driven', true)
  );
  RETURN completion || jsonb_build_object(
    'handoff', true,
    'successor_task_ids', successor_ids,
    'free_form_handoff_supported', false
  );
END;
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
      'assignee', CASE WHEN profile.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', profile.id, 'full_name', profile.full_name, 'display_name', profile.display_name,
        'display_name_ar', profile.display_name_ar, 'role', profile.role,
        'job_title', profile.job_title, 'employee_id', profile.employee_id
      ) END,
      'profiles', CASE WHEN profile.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', profile.id, 'full_name', profile.full_name, 'display_name', profile.display_name,
        'display_name_ar', profile.display_name_ar, 'role', profile.role,
        'job_title', profile.job_title, 'employee_id', profile.employee_id
      ) END,
      'projects', CASE WHEN project.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', project.id, 'project_name', project.project_name
      ) END,
      'dependency_blocked', public.task_dependency_blocked_visible(task.id, auth.uid()),
      'blocking_task_title', (
        SELECT predecessor.title
        FROM public.task_dependencies dependency
        JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
        WHERE dependency.successor_task_id = task.id
          AND dependency.removed_at IS NULL
          AND predecessor.status <> 'completed'
          AND public.can_view_task_dependency(predecessor.id, task.id, auth.uid())
        ORDER BY dependency.created_at ASC
        LIMIT 1
      )
    )
  FROM public.tasks task
  LEFT JOIN public.profiles profile ON profile.id = task.assignee_id
  LEFT JOIN public.projects project ON project.id = task.project_id
  WHERE auth.uid() IS NOT NULL AND public.can_access_task(task.id, auth.uid())
  ORDER BY task.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_my_day()
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
WITH scoped AS (
  SELECT task.*,
    public.task_dependency_blocked_visible(task.id, auth.uid()) AS dependency_blocked,
    (
      SELECT predecessor.title
      FROM public.task_dependencies dependency
      JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
      WHERE dependency.successor_task_id = task.id
        AND dependency.removed_at IS NULL
        AND predecessor.status <> 'completed'
        AND public.can_view_task_dependency(predecessor.id, task.id, auth.uid())
      ORDER BY dependency.created_at ASC
      LIMIT 1
    ) AS blocking_task_title
  FROM public.tasks task
  WHERE auth.uid() IS NOT NULL
    AND task.archived_at IS NULL
    AND public.can_access_task(task.id, auth.uid())
    AND (
      task.assignee_id = auth.uid()
      OR auth.uid() = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
      OR (task.assignee_id IS NULL AND COALESCE(cardinality(task.assignee_ids), 0) = 0 AND task.created_by = auth.uid())
    )
), classified AS (
  SELECT scoped.*, CASE
    WHEN scoped.status = 'completed' AND scoped.completed_at::date = CURRENT_DATE THEN 'COMPLETED_TODAY'
    WHEN scoped.work_state = 'WAITING' THEN 'WAITING'
    WHEN scoped.work_state = 'BLOCKED' THEN 'BLOCKED'
    WHEN scoped.dependency_blocked THEN 'WAITING'
    WHEN scoped.status <> 'completed' AND scoped.due_date < CURRENT_DATE THEN 'OVERDUE'
    WHEN scoped.status <> 'completed' AND (
      LOWER(COALESCE(scoped.priority, '')) IN ('critical', 'urgent', 'high')
      OR scoped.started_at IS NOT NULL
      OR (scoped.due_date IS NOT NULL AND scoped.due_date <= CURRENT_DATE + 1)
    ) THEN 'DO_NOW'
    WHEN scoped.status <> 'completed' AND scoped.due_date = CURRENT_DATE THEN 'DUE_TODAY'
    WHEN scoped.status <> 'completed' THEN 'NEXT'
    ELSE NULL
  END AS my_day_section
  FROM scoped
), explained AS (
  SELECT classified.*, CASE
    WHEN classified.dependency_blocked THEN 'Waiting for previous task: ' || COALESCE(classified.blocking_task_title, 'previous task')
    WHEN classified.my_day_section = 'WAITING' THEN 'Waiting for ' || REPLACE(INITCAP(LOWER(COALESCE(classified.waiting_category, 'dependency'))), '_', ' ')
    WHEN classified.my_day_section = 'BLOCKED' THEN 'Blocked: ' || REPLACE(INITCAP(LOWER(COALESCE(classified.blocked_category, 'other'))), '_', ' ')
    WHEN classified.my_day_section = 'COMPLETED_TODAY' THEN 'Completed today'
    WHEN classified.my_day_section = 'OVERDUE' THEN 'Overdue by ' || GREATEST(CURRENT_DATE - classified.due_date, 1) || ' day(s)'
    WHEN LOWER(COALESCE(classified.priority, '')) IN ('critical', 'urgent', 'high') THEN INITCAP(classified.priority) || ' priority'
    WHEN classified.due_date = CURRENT_DATE THEN 'Due today'
    WHEN classified.started_at IS NOT NULL THEN 'Already started'
    WHEN classified.due_date IS NOT NULL AND classified.due_date <= CURRENT_DATE + 1 THEN 'Due soon'
    ELSE 'Upcoming task'
  END AS my_day_reason
  FROM classified
  WHERE classified.my_day_section IS NOT NULL
)
SELECT to_jsonb(explained)
FROM explained
ORDER BY CASE explained.my_day_section
  WHEN 'DO_NOW' THEN 1 WHEN 'DUE_TODAY' THEN 2 WHEN 'WAITING' THEN 3
  WHEN 'BLOCKED' THEN 4 WHEN 'OVERDUE' THEN 5 WHEN 'NEXT' THEN 6
  WHEN 'COMPLETED_TODAY' THEN 7 ELSE 8 END,
  explained.due_date NULLS LAST, explained.priority DESC, explained.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.list_task_activity_secure(p_task_id uuid)
RETURNS SETOF public.task_activity
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT activity.*
  FROM public.task_activity activity
  WHERE activity.task_id = p_task_id
    AND auth.uid() IS NOT NULL
    AND public.task_activity_dependency_visible(
      activity.task_id, activity.action, activity.metadata, auth.uid()
    )
  ORDER BY activity.created_at DESC;
$$;

ALTER TABLE public.task_dependencies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS task_dependencies_secure_select ON public.task_dependencies;
CREATE POLICY task_dependencies_secure_select ON public.task_dependencies
  FOR SELECT TO authenticated
  USING (public.can_view_task_dependency(predecessor_task_id, successor_task_id, auth.uid()));

DROP POLICY IF EXISTS task_activity_secure_select ON public.task_activity;
CREATE POLICY task_activity_secure_select ON public.task_activity FOR SELECT TO authenticated
  USING (public.task_activity_dependency_visible(task_id, action, metadata, auth.uid()));

NOTIFY pgrst, 'reload schema';
COMMIT;
