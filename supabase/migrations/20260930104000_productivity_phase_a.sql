-- Reviewed production migration generated from the verified service artifact.
-- Source artifact: productivity_phase_a.sql
-- No environment reference, test identity, synthetic fixture, or cleanup harness is included.
-- HR.sys Productivity Phase A (reviewed production)
-- My Day, quick task actions, waiting/blocker state and durable history.
-- This artifact is intentionally kept outside supabase/migrations so it cannot
-- be applied to production accidentally.
BEGIN;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS work_state text NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS waiting_category text,
  ADD COLUMN IF NOT EXISTS waiting_related_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS waiting_note text,
  ADD COLUMN IF NOT EXISTS waiting_since timestamptz,
  ADD COLUMN IF NOT EXISTS blocked_category text,
  ADD COLUMN IF NOT EXISTS blocked_related_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS blocked_note text,
  ADD COLUMN IF NOT EXISTS blocked_since timestamptz,
  ADD COLUMN IF NOT EXISTS resume_status text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.tasks'::regclass AND conname = 'tasks_work_state_check'
  ) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_work_state_check CHECK (work_state IN ('ACTIVE', 'WAITING', 'BLOCKED'));
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.task_waiting_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  category text NOT NULL,
  related_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  note text,
  started_at timestamptz NOT NULL DEFAULT now(),
  resumed_at timestamptz,
  resumed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.task_blocker_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  category text NOT NULL,
  related_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS task_my_day_state_idx ON public.tasks(work_state, due_date, priority);
CREATE INDEX IF NOT EXISTS task_waiting_history_task_idx ON public.task_waiting_history(task_id, started_at DESC);
CREATE INDEX IF NOT EXISTS task_blocker_history_task_idx ON public.task_blocker_history(task_id, created_at DESC);

ALTER TABLE public.task_waiting_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_blocker_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS task_waiting_history_secure_select ON public.task_waiting_history;
DROP POLICY IF EXISTS task_blocker_history_secure_select ON public.task_blocker_history;
CREATE POLICY task_waiting_history_secure_select ON public.task_waiting_history
  FOR SELECT TO authenticated USING (public.can_access_task(task_id, auth.uid()));
CREATE POLICY task_blocker_history_secure_select ON public.task_blocker_history
  FOR SELECT TO authenticated USING (public.can_access_task(task_id, auth.uid()));
REVOKE ALL ON public.task_waiting_history, public.task_blocker_history FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.productivity_validate_category(p_category text, p_blocked boolean DEFAULT false)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE value text := UPPER(BTRIM(COALESCE(p_category, '')));
BEGIN
  IF p_blocked THEN
    RETURN value IN ('CLIENT', 'SUPPLIER', 'ANOTHER_EMPLOYEE', 'MANAGEMENT', 'APPROVAL', 'MISSING_INFORMATION', 'TECHNICAL_PROBLEM', 'OTHER');
  END IF;
  RETURN value IN ('CLIENT', 'SUPPLIER', 'MANAGEMENT', 'APPROVAL', 'DESIGN', 'PRODUCTION', 'ANOTHER_EMPLOYEE', 'MISSING_INFORMATION', 'OTHER');
END;
$$;

-- Execution actions intentionally mirror the existing change_task_status
-- assignee rule. This is narrower than task management/edit/delete access and
-- does not broaden can_manage_task or permit ownership changes.
CREATE OR REPLACE FUNCTION public.can_execute_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tasks task
    JOIN public.profiles profile ON profile.id = p_user_id
    WHERE task.id = p_task_id
      AND p_user_id IS NOT NULL
      AND profile.is_active IS DISTINCT FROM false
      AND (
        profile.id IN (task.created_by, task.assignee_id, task.supervisor_id)
        OR profile.id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
        OR UPPER(COALESCE(profile.role, '')) IN ('ADMIN', 'MANAGER', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'CEO', 'GM', 'GENERAL MANAGER')
        OR UPPER(COALESCE(profile.job_title, '')) IN ('CEO', 'GM', 'GENERAL MANAGER')
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.get_my_day()
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
WITH scoped AS (
  SELECT task.*
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

CREATE OR REPLACE FUNCTION public.get_my_completed_today()
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT item FROM public.get_my_day() item WHERE item->>'my_day_section' = 'COMPLETED_TODAY';
$$;

CREATE OR REPLACE FUNCTION public.start_task(p_task_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE task_row public.tasks%ROWTYPE; changed boolean := false;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_execute_task(p_task_id, auth.uid()) THEN
    RAISE EXCEPTION 'Task access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
  IF task_row.status = 'completed' THEN RAISE EXCEPTION 'Completed tasks cannot be started' USING ERRCODE = '22023'; END IF;
  IF task_row.work_state <> 'ACTIVE' THEN RAISE EXCEPTION 'Resume the task before starting work' USING ERRCODE = '22023'; END IF;
  IF task_row.status <> 'in_progress' OR task_row.started_at IS NULL THEN
    UPDATE public.tasks SET status = 'in_progress', started_at = COALESCE(started_at, now()) WHERE id = p_task_id;
    changed := true;
    IF task_row.status <> 'in_progress' THEN
      INSERT INTO public.task_activity(task_id, actor_id, action, from_status, to_status, metadata)
      VALUES (p_task_id, auth.uid(), 'TASK_STARTED', task_row.status, 'in_progress', '{}'::jsonb);
    ELSE
      INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
      VALUES (p_task_id, auth.uid(), 'TASK_STARTED', '{}'::jsonb);
    END IF;
  END IF;
  RETURN jsonb_build_object('task_id', p_task_id, 'status', 'in_progress', 'started_at', (SELECT started_at FROM public.tasks WHERE id = p_task_id), 'changed', changed, 'actor_id', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_task_waiting(p_task_id uuid, p_category text, p_related_user_id uuid DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE task_row public.tasks%ROWTYPE; category_value text := UPPER(BTRIM(COALESCE(p_category, ''))); now_value timestamptz := now();
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_execute_task(p_task_id, auth.uid()) THEN RAISE EXCEPTION 'Task access denied' USING ERRCODE = '42501'; END IF;
  IF NOT public.productivity_validate_category(category_value, false) THEN RAISE EXCEPTION 'Invalid waiting category' USING ERRCODE = '22023'; END IF;
  IF p_related_user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_related_user_id AND is_active IS DISTINCT FROM false) THEN RAISE EXCEPTION 'Related employee is invalid' USING ERRCODE = '22023'; END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
  IF task_row.status = 'completed' THEN RAISE EXCEPTION 'Completed tasks cannot wait' USING ERRCODE = '22023'; END IF;
  IF task_row.work_state = 'WAITING' THEN RETURN jsonb_build_object('task_id', p_task_id, 'work_state', 'WAITING', 'changed', false, 'actor_id', auth.uid()); END IF;
  UPDATE public.tasks SET work_state = 'WAITING', resume_status = status, waiting_category = category_value, waiting_related_user_id = p_related_user_id, waiting_note = NULLIF(BTRIM(p_note), ''), waiting_since = now_value, blocked_category = NULL, blocked_related_user_id = NULL, blocked_note = NULL, blocked_since = NULL WHERE id = p_task_id;
  INSERT INTO public.task_waiting_history(task_id, actor_id, category, related_user_id, note, started_at) VALUES (p_task_id, auth.uid(), category_value, p_related_user_id, NULLIF(BTRIM(p_note), ''), now_value);
  INSERT INTO public.task_activity(task_id, actor_id, action, metadata) VALUES (p_task_id, auth.uid(), 'TASK_WAITING', jsonb_build_object('category', category_value, 'related_user_id', p_related_user_id, 'note', NULLIF(BTRIM(p_note), '')));
  PERFORM public.queue_task_notification(p_task_id, auth.uid(), 'task_waiting', 'Task is waiting: ' || task_row.title);
  RETURN jsonb_build_object('task_id', p_task_id, 'work_state', 'WAITING', 'waiting_category', category_value, 'waiting_since', now_value, 'actor_id', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_task_blocked(p_task_id uuid, p_category text, p_related_user_id uuid DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE task_row public.tasks%ROWTYPE; category_value text := UPPER(BTRIM(COALESCE(p_category, ''))); now_value timestamptz := now();
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_execute_task(p_task_id, auth.uid()) THEN RAISE EXCEPTION 'Task access denied' USING ERRCODE = '42501'; END IF;
  IF NOT public.productivity_validate_category(category_value, true) THEN RAISE EXCEPTION 'Invalid blocker category' USING ERRCODE = '22023'; END IF;
  IF p_related_user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_related_user_id AND is_active IS DISTINCT FROM false) THEN RAISE EXCEPTION 'Related employee is invalid' USING ERRCODE = '22023'; END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
  IF task_row.status = 'completed' THEN RAISE EXCEPTION 'Completed tasks cannot be blocked' USING ERRCODE = '22023'; END IF;
  IF task_row.work_state = 'BLOCKED' THEN RETURN jsonb_build_object('task_id', p_task_id, 'work_state', 'BLOCKED', 'changed', false, 'actor_id', auth.uid()); END IF;
  UPDATE public.tasks SET work_state = 'BLOCKED', resume_status = status, blocked_category = category_value, blocked_related_user_id = p_related_user_id, blocked_note = NULLIF(BTRIM(p_note), ''), blocked_since = now_value, waiting_category = NULL, waiting_related_user_id = NULL, waiting_note = NULL, waiting_since = NULL WHERE id = p_task_id;
  INSERT INTO public.task_blocker_history(task_id, actor_id, category, related_user_id, note, created_at) VALUES (p_task_id, auth.uid(), category_value, p_related_user_id, NULLIF(BTRIM(p_note), ''), now_value);
  INSERT INTO public.task_activity(task_id, actor_id, action, metadata) VALUES (p_task_id, auth.uid(), 'TASK_BLOCKED', jsonb_build_object('category', category_value, 'related_user_id', p_related_user_id, 'note', NULLIF(BTRIM(p_note), '')));
  PERFORM public.queue_task_notification(p_task_id, auth.uid(), 'task_blocked', 'Task is blocked: ' || task_row.title);
  RETURN jsonb_build_object('task_id', p_task_id, 'work_state', 'BLOCKED', 'blocked_category', category_value, 'blocked_since', now_value, 'actor_id', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.resume_task(p_task_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE task_row public.tasks%ROWTYPE; next_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_execute_task(p_task_id, auth.uid()) THEN RAISE EXCEPTION 'Task access denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
  IF task_row.work_state = 'ACTIVE' THEN RETURN jsonb_build_object('task_id', p_task_id, 'work_state', 'ACTIVE', 'changed', false, 'actor_id', auth.uid()); END IF;
  next_status := COALESCE(NULLIF(task_row.resume_status, ''), CASE WHEN task_row.started_at IS NULL THEN 'todo' ELSE 'in_progress' END);
  UPDATE public.tasks SET work_state = 'ACTIVE', status = next_status, waiting_category = NULL, waiting_related_user_id = NULL, waiting_note = NULL, waiting_since = NULL, blocked_category = NULL, blocked_related_user_id = NULL, blocked_note = NULL, blocked_since = NULL, resume_status = NULL WHERE id = p_task_id;
  UPDATE public.task_waiting_history SET resumed_at = now(), resumed_by = auth.uid() WHERE task_id = p_task_id AND resumed_at IS NULL;
  UPDATE public.task_blocker_history SET resolved_at = now(), resolved_by = auth.uid() WHERE task_id = p_task_id AND resolved_at IS NULL;
  INSERT INTO public.task_activity(task_id, actor_id, action, from_status, to_status, metadata) VALUES (p_task_id, auth.uid(), 'TASK_RESUMED', task_row.status, next_status, jsonb_build_object('previous_work_state', task_row.work_state));
  PERFORM public.queue_task_notification(p_task_id, auth.uid(), 'task_resumed', 'Task resumed: ' || task_row.title);
  RETURN jsonb_build_object('task_id', p_task_id, 'work_state', 'ACTIVE', 'status', next_status, 'actor_id', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_task_productivity(p_task_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE task_row public.tasks%ROWTYPE; changed boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_execute_task(p_task_id, auth.uid()) THEN RAISE EXCEPTION 'Task access denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
  changed := task_row.status <> 'completed';
  PERFORM public.change_task_status(p_task_id, 'completed');
  UPDATE public.tasks SET completed_at = COALESCE(completed_at, now()), work_state = 'ACTIVE', waiting_category = NULL, waiting_related_user_id = NULL, waiting_note = NULL, waiting_since = NULL, blocked_category = NULL, blocked_related_user_id = NULL, blocked_note = NULL, blocked_since = NULL, resume_status = NULL WHERE id = p_task_id;
  IF changed THEN INSERT INTO public.task_activity(task_id, actor_id, action, metadata) VALUES (p_task_id, auth.uid(), 'TASK_COMPLETED', '{}'::jsonb); END IF;
  RETURN jsonb_build_object('task_id', p_task_id, 'status', 'completed', 'completed_at', (SELECT completed_at FROM public.tasks WHERE id = p_task_id), 'actor_id', auth.uid(), 'changed', changed);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_task_work_states_secure()
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT to_jsonb(task)
    || jsonb_build_object('assignee_name', COALESCE(assignee.full_name, assignee.display_name, 'Unassigned'), 'project_name', project.project_name)
  FROM public.tasks task
  LEFT JOIN public.profiles assignee ON assignee.id = COALESCE(task.assignee_id, task.assignee_ids[1])
  LEFT JOIN public.projects project ON project.id = task.project_id
  JOIN public.profiles viewer ON viewer.id = auth.uid()
  WHERE auth.uid() IS NOT NULL
    AND viewer.is_active IS DISTINCT FROM false
    AND UPPER(COALESCE(viewer.role, '')) IN ('ADMIN', 'MANAGER', 'SUPERVISOR', 'CEO', 'GM', 'GENERAL MANAGER')
    AND task.archived_at IS NULL AND task.work_state IN ('WAITING', 'BLOCKED')
    AND public.can_access_task(task.id, auth.uid())
  ORDER BY COALESCE(task.waiting_since, task.blocked_since, task.updated_at) ASC;
$$;

CREATE OR REPLACE FUNCTION public.list_task_work_history_secure(p_task_id uuid)
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH entries AS (
    SELECT to_jsonb(history_row) || jsonb_build_object('history_type', 'WAITING') AS payload,
           history_row.started_at AS sort_at
    FROM public.task_waiting_history history_row
    WHERE history_row.task_id = p_task_id
      AND auth.uid() IS NOT NULL
      AND public.can_access_task(p_task_id, auth.uid())
    UNION ALL
    SELECT to_jsonb(history_row) || jsonb_build_object('history_type', 'BLOCKED') AS payload,
           history_row.created_at AS sort_at
    FROM public.task_blocker_history history_row
    WHERE history_row.task_id = p_task_id
      AND auth.uid() IS NOT NULL
      AND public.can_access_task(p_task_id, auth.uid())
  )
  SELECT payload FROM entries ORDER BY sort_at DESC;
$$;

REVOKE ALL ON FUNCTION public.productivity_validate_category(text, boolean), public.can_execute_task(uuid, uuid), public.get_my_day(), public.get_my_completed_today(), public.start_task(uuid), public.mark_task_waiting(uuid, text, uuid, text), public.mark_task_blocked(uuid, text, uuid, text), public.resume_task(uuid), public.complete_task_productivity(uuid), public.list_task_work_states_secure(), public.list_task_work_history_secure(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_day(), public.get_my_completed_today(), public.start_task(uuid), public.mark_task_waiting(uuid, text, uuid, text), public.mark_task_blocked(uuid, text, uuid, text), public.resume_task(uuid), public.complete_task_productivity(uuid), public.list_task_work_states_secure(), public.list_task_work_history_secure(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
