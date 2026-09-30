-- Reviewed production migration generated from the verified service artifact.
-- Source artifact: productivity_phase_b.sql
-- No environment reference, test identity, synthetic fixture, or cleanup harness is included.
-- HR.sys Productivity Phase B (reviewed production)
-- Task dependencies and dependency-driven completion/handoff.
-- This migration is intentionally kept outside supabase/migrations so it
-- cannot be applied to production accidentally.
BEGIN;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS dependency_ready_notified_at timestamptz;

CREATE TABLE IF NOT EXISTS public.task_dependencies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  predecessor_task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  successor_task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  removed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  removed_at timestamptz,
  CONSTRAINT task_dependencies_distinct_tasks CHECK (predecessor_task_id <> successor_task_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS task_dependencies_active_pair_idx
  ON public.task_dependencies(predecessor_task_id, successor_task_id)
  WHERE removed_at IS NULL;
CREATE INDEX IF NOT EXISTS task_dependencies_predecessor_idx
  ON public.task_dependencies(predecessor_task_id) WHERE removed_at IS NULL;
CREATE INDEX IF NOT EXISTS task_dependencies_successor_idx
  ON public.task_dependencies(successor_task_id) WHERE removed_at IS NULL;

CREATE OR REPLACE FUNCTION public.validate_task_dependency_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  predecessor_project uuid;
  successor_project uuid;
BEGIN
  SELECT project_id INTO predecessor_project FROM public.tasks WHERE id = NEW.predecessor_task_id;
  SELECT project_id INTO successor_project FROM public.tasks WHERE id = NEW.successor_task_id;
  IF predecessor_project IS DISTINCT FROM successor_project THEN
    RAISE EXCEPTION 'Task dependencies must stay within the same project context' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS task_dependency_context_guard ON public.task_dependencies;
CREATE TRIGGER task_dependency_context_guard
BEFORE INSERT OR UPDATE OF predecessor_task_id, successor_task_id
ON public.task_dependencies
FOR EACH ROW EXECUTE FUNCTION public.validate_task_dependency_context();

CREATE OR REPLACE FUNCTION public.task_dependency_would_cycle(
  p_predecessor_task_id uuid,
  p_successor_task_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH RECURSIVE reachable(task_id) AS (
    SELECT p_successor_task_id
    UNION
    SELECT dependency.successor_task_id
    FROM public.task_dependencies dependency
    JOIN reachable node ON node.task_id = dependency.predecessor_task_id
    WHERE dependency.removed_at IS NULL
  )
  SELECT EXISTS (
    SELECT 1 FROM reachable WHERE task_id = p_predecessor_task_id
  );
$$;

CREATE OR REPLACE FUNCTION public.task_dependency_blocked(p_task_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.task_dependencies dependency
    JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
    WHERE dependency.successor_task_id = p_task_id
      AND dependency.removed_at IS NULL
      AND predecessor.status <> 'completed'
  );
$$;

-- Phase B extends the existing Phase A execution RPCs with the same
-- authoritative dependency guard used by status changes and completion.
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
  IF public.task_dependency_blocked(p_task_id) THEN
    RAISE EXCEPTION 'Task is waiting for a previous task to complete' USING ERRCODE = '42501';
  END IF;
  IF task_row.work_state <> 'ACTIVE' THEN RAISE EXCEPTION 'Resume the task before starting work' USING ERRCODE = '22023'; END IF;
  IF task_row.status <> 'in_progress' OR task_row.started_at IS NULL THEN
    UPDATE public.tasks SET status = 'in_progress', started_at = COALESCE(started_at, now()) WHERE id = p_task_id;
    changed := true;
    INSERT INTO public.task_activity(task_id, actor_id, action, from_status, to_status, metadata)
    VALUES (p_task_id, auth.uid(), 'TASK_STARTED', task_row.status, 'in_progress', '{}'::jsonb);
  END IF;
  RETURN jsonb_build_object('task_id', p_task_id, 'status', 'in_progress', 'started_at', (SELECT started_at FROM public.tasks WHERE id = p_task_id), 'changed', changed, 'actor_id', auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.resume_task(p_task_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE task_row public.tasks%ROWTYPE; next_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_execute_task(p_task_id, auth.uid()) THEN
    RAISE EXCEPTION 'Task access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
  IF public.task_dependency_blocked(p_task_id) THEN
    RAISE EXCEPTION 'Task is waiting for a previous task to complete' USING ERRCODE = '42501';
  END IF;
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

CREATE OR REPLACE FUNCTION public.create_task_dependency(
  p_predecessor_task_id uuid,
  p_successor_task_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  dependency_row public.task_dependencies;
  predecessor_task public.tasks;
  successor_task public.tasks;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE = '42501';
  END IF;
  IF p_predecessor_task_id IS NULL OR p_successor_task_id IS NULL
     OR p_predecessor_task_id = p_successor_task_id THEN
    RAISE EXCEPTION 'A task cannot depend on itself' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO predecessor_task FROM public.tasks WHERE id = p_predecessor_task_id;
  SELECT * INTO successor_task FROM public.tasks WHERE id = p_successor_task_id;
  IF predecessor_task.id IS NULL OR successor_task.id IS NULL THEN
    RAISE EXCEPTION 'Both tasks must exist' USING ERRCODE = 'P0002';
  END IF;
  IF NOT public.can_manage_task(p_predecessor_task_id, auth.uid())
     OR NOT public.can_manage_task(p_successor_task_id, auth.uid()) THEN
    RAISE EXCEPTION 'Only an authorized task manager can create dependencies' USING ERRCODE = '42501';
  END IF;
  IF predecessor_task.project_id IS DISTINCT FROM successor_task.project_id THEN
    RAISE EXCEPTION 'Task dependencies must stay within the same project context' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.task_dependencies
    WHERE predecessor_task_id = p_predecessor_task_id
      AND successor_task_id = p_successor_task_id
      AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'This task dependency already exists' USING ERRCODE = '23505';
  END IF;
  IF public.task_dependency_would_cycle(p_predecessor_task_id, p_successor_task_id) THEN
    RAISE EXCEPTION 'This dependency would create a circular workflow' USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.task_dependencies(predecessor_task_id, successor_task_id, created_by)
  VALUES (p_predecessor_task_id, p_successor_task_id, auth.uid())
  RETURNING * INTO dependency_row;

  INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
  VALUES
    (p_predecessor_task_id, auth.uid(), 'TASK_DEPENDENCY_CREATED',
      jsonb_build_object('dependency_id', dependency_row.id, 'successor_task_id', p_successor_task_id)),
    (p_successor_task_id, auth.uid(), 'TASK_DEPENDENCY_CREATED',
      jsonb_build_object('dependency_id', dependency_row.id, 'predecessor_task_id', p_predecessor_task_id));

  RETURN jsonb_build_object(
    'id', dependency_row.id,
    'predecessor_task_id', dependency_row.predecessor_task_id,
    'successor_task_id', dependency_row.successor_task_id,
    'created_by', dependency_row.created_by,
    'created_at', dependency_row.created_at,
    'is_satisfied', predecessor_task.status = 'completed'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_task_dependency(p_dependency_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  dependency_row public.task_dependencies;
BEGIN
  SELECT * INTO dependency_row
  FROM public.task_dependencies
  WHERE id = p_dependency_id AND removed_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF auth.uid() IS NULL
     OR NOT public.can_manage_task(dependency_row.predecessor_task_id, auth.uid())
     OR NOT public.can_manage_task(dependency_row.successor_task_id, auth.uid()) THEN
    RAISE EXCEPTION 'Only an authorized task manager can remove dependencies' USING ERRCODE = '42501';
  END IF;

  UPDATE public.task_dependencies
  SET removed_by = auth.uid(), removed_at = now()
  WHERE id = dependency_row.id;

  INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
  VALUES
    (dependency_row.predecessor_task_id, auth.uid(), 'TASK_DEPENDENCY_REMOVED',
      jsonb_build_object('dependency_id', dependency_row.id, 'successor_task_id', dependency_row.successor_task_id)),
    (dependency_row.successor_task_id, auth.uid(), 'TASK_DEPENDENCY_REMOVED',
      jsonb_build_object('dependency_id', dependency_row.id, 'predecessor_task_id', dependency_row.predecessor_task_id));
  RETURN true;
END;
$$;

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
    AND public.can_access_task(p_task_id, auth.uid())
  ORDER BY dependency.created_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.list_task_dependency_history_secure(p_task_id uuid)
RETURNS SETOF public.task_activity
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT *
  FROM public.task_activity
  WHERE task_id = p_task_id
    AND action IN (
      'TASK_DEPENDENCY_CREATED',
      'TASK_DEPENDENCY_REMOVED',
      'TASK_DEPENDENCY_BLOCKED',
      'TASK_DEPENDENCY_PREDECESSOR_COMPLETED',
      'TASK_DEPENDENCY_READY',
      'TASK_HANDOFF',
      'TASK_HANDOFF_NOTIFIED'
    )
    AND auth.uid() IS NOT NULL
    AND public.can_access_task(p_task_id, auth.uid())
  ORDER BY created_at DESC;
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
    AND public.can_access_task(successor.id, auth.uid())
  ORDER BY dependency.created_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.activate_task_successors(p_predecessor_task_id uuid, p_actor_id uuid DEFAULT auth.uid())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  successor_task public.tasks;
  all_satisfied boolean;
  activated jsonb := '[]'::jsonb;
BEGIN
  FOR successor_task IN
    SELECT task.*
    FROM public.tasks task
    JOIN public.task_dependencies dependency
      ON dependency.successor_task_id = task.id
     AND dependency.predecessor_task_id = p_predecessor_task_id
     AND dependency.removed_at IS NULL
    WHERE task.archived_at IS NULL
    FOR UPDATE
  LOOP
    SELECT COALESCE(bool_and(predecessor.status = 'completed'), false)
    INTO all_satisfied
    FROM public.task_dependencies dependency
    JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
    WHERE dependency.successor_task_id = successor_task.id
      AND dependency.removed_at IS NULL;

    IF all_satisfied THEN
      IF successor_task.dependency_ready_notified_at IS NULL THEN
        UPDATE public.tasks
        SET dependency_ready_notified_at = now()
        WHERE id = successor_task.id;

        INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
        VALUES
          (successor_task.id, p_actor_id, 'TASK_DEPENDENCY_PREDECESSOR_COMPLETED',
            jsonb_build_object('predecessor_task_id', p_predecessor_task_id)),
          (successor_task.id, p_actor_id, 'TASK_DEPENDENCY_READY',
            jsonb_build_object('predecessor_task_id', p_predecessor_task_id));
        PERFORM public.queue_task_notification(
          successor_task.id,
          p_actor_id,
          'task_ready',
          'Task is ready for you: ' || successor_task.title
        );
        activated := activated || jsonb_build_array(successor_task.id);
      END IF;
    ELSE
      UPDATE public.tasks
      SET dependency_ready_notified_at = NULL
      WHERE id = successor_task.id;
      INSERT INTO public.task_activity(task_id, actor_id, action, metadata)
      VALUES (
        successor_task.id,
        p_actor_id,
        'TASK_DEPENDENCY_BLOCKED',
        jsonb_build_object('predecessor_task_id', p_predecessor_task_id)
      );
    END IF;
  END LOOP;
  RETURN activated;
END;
$$;

CREATE OR REPLACE FUNCTION public.change_task_status(p_task_id uuid, p_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  task_row public.tasks%ROWTYPE;
  next_status text := NULLIF(BTRIM(COALESCE(p_status, '')), '');
  can_execute boolean := false;
BEGIN
  IF auth.uid() IS NULL OR next_status IS NULL THEN
    RAISE EXCEPTION 'A task and status are required' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id = auth.uid()
      AND profile.is_active IS DISTINCT FROM false
      AND (
        profile.id IN (task_row.created_by, task_row.assignee_id, task_row.supervisor_id)
        OR auth.uid() = ANY(COALESCE(task_row.assignee_ids, '{}'::uuid[]))
        OR UPPER(COALESCE(profile.role, '')) IN ('ADMIN','MANAGER','OWNER','ROLE SYSTEM ADMIN','SYSTEM ADMIN','CEO','GM','GENERAL MANAGER')
        OR UPPER(COALESCE(profile.job_title, '')) IN ('CEO','GM','GENERAL MANAGER')
      )
  ) INTO can_execute;
  IF NOT can_execute THEN
    RAISE EXCEPTION 'You are not authorized to change this task' USING ERRCODE = '42501';
  END IF;
  IF next_status IN ('in_progress','review','completed') AND public.task_dependency_blocked(p_task_id) THEN
    RAISE EXCEPTION 'Task is waiting for a previous task to complete' USING ERRCODE = '42501';
  END IF;

  UPDATE public.tasks
  SET status = next_status,
      completed_at = CASE WHEN next_status = 'completed' THEN COALESCE(completed_at, now()) ELSE completed_at END
  WHERE id = p_task_id;
  IF next_status = 'completed' AND task_row.status IS DISTINCT FROM 'completed' THEN
    PERFORM public.activate_task_successors(p_task_id, auth.uid());
  ELSIF task_row.status = 'completed' AND next_status IS DISTINCT FROM 'completed' THEN
    -- Reopening a predecessor blocks successors again and allows a fresh
    -- readiness notification after it is completed the next time.
    PERFORM public.activate_task_successors(p_task_id, auth.uid());
  END IF;
  RETURN jsonb_build_object(
    'task_id', task_row.id,
    'from_status', task_row.status,
    'to_status', next_status,
    'actor_id', auth.uid()
  );
END;
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
  PERFORM public.change_task_status(p_task_id, 'completed');
  UPDATE public.tasks
  SET completed_at = COALESCE(completed_at, now()),
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
  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'status', 'completed',
    'completed_at', (SELECT completed_at FROM public.tasks WHERE id = p_task_id),
    'actor_id', auth.uid(),
    'changed', changed,
    'activated_successors', activated
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
      'dependency_blocked', public.task_dependency_blocked(task.id),
      'blocking_task_title', (
        SELECT predecessor.title
        FROM public.task_dependencies dependency
        JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
        WHERE dependency.successor_task_id = task.id
          AND dependency.removed_at IS NULL
          AND predecessor.status <> 'completed'
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
    public.task_dependency_blocked(task.id) AS dependency_blocked,
    (
      SELECT predecessor.title
      FROM public.task_dependencies dependency
      JOIN public.tasks predecessor ON predecessor.id = dependency.predecessor_task_id
      WHERE dependency.successor_task_id = task.id
        AND dependency.removed_at IS NULL
        AND predecessor.status <> 'completed'
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

ALTER TABLE public.task_dependencies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS task_dependencies_secure_select ON public.task_dependencies;
CREATE POLICY task_dependencies_secure_select ON public.task_dependencies
  FOR SELECT TO authenticated
  USING (
    public.can_access_task(predecessor_task_id, auth.uid())
    OR public.can_access_task(successor_task_id, auth.uid())
  );

REVOKE ALL ON public.task_dependencies FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION
  public.validate_task_dependency_context(),
  public.task_dependency_would_cycle(uuid, uuid),
  public.task_dependency_blocked(uuid),
  public.activate_task_successors(uuid, uuid),
  public.create_task_dependency(uuid, uuid),
  public.remove_task_dependency(uuid),
  public.list_task_dependencies_secure(uuid),
  public.list_task_dependency_history_secure(uuid),
  public.list_task_dependency_blockers_secure(),
  public.complete_and_hand_off_task(uuid, uuid)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.create_task_dependency(uuid, uuid),
  public.remove_task_dependency(uuid),
  public.list_task_dependencies_secure(uuid),
  public.list_task_dependency_history_secure(uuid),
  public.list_task_dependency_blockers_secure(),
  public.complete_and_hand_off_task(uuid, uuid)
TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
