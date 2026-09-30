-- Reviewed production migration generated from the verified service artifact.
-- Source artifact: productivity_phase_c.sql
-- No environment reference, test identity, synthetic fixture, or cleanup harness is included.
-- Productivity Phase C: authoritative Project Command Center aggregation.
-- reviewed production artifact.  It is intentionally kept outside supabase/migrations.
-- The function exposes operational/project-health data only; financial columns
-- are never selected into the mobile/web command-center contract.
BEGIN;

CREATE OR REPLACE FUNCTION public.list_project_command_center(
  p_limit integer DEFAULT 50,
  p_only_attention boolean DEFAULT false,
  p_upcoming_days integer DEFAULT NULL
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 1000);
BEGIN
  IF v_user IS NULL OR NOT public.is_project_portfolio_admin(v_user) THEN
    RAISE EXCEPTION 'Project command center access denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH scoped_projects AS (
    SELECT project.*,
      owner_profile.full_name AS owner_full_name,
      owner_profile.display_name AS owner_display_name,
      owner_profile.display_name_ar AS owner_display_name_ar,
      owner_profile.employee_id AS owner_employee_id
    FROM public.projects project
    LEFT JOIN public.profiles owner_profile ON owner_profile.id = project.project_manager_id
    WHERE project.lifecycle_status <> 'CANCELLED'
      AND public.can_access_project(project.id, v_user)
  ), task_metrics AS (
    SELECT project.id AS project_id,
      COUNT(task.id)::integer AS task_count,
      COUNT(task.id) FILTER (WHERE task.status = 'completed')::integer AS completed_task_count,
      COUNT(task.id) FILTER (WHERE task.status <> 'completed' AND task.due_date < CURRENT_DATE)::integer AS overdue_task_count,
      COUNT(task.id) FILTER (WHERE task.status <> 'completed' AND task.due_date = CURRENT_DATE)::integer AS due_today_task_count,
      COUNT(task.id) FILTER (WHERE task.status <> 'completed' AND task.due_date >= CURRENT_DATE AND task.due_date <= CURRENT_DATE + 3 AND LOWER(COALESCE(task.priority, '')) IN ('high', 'urgent', 'critical'))::integer AS critical_due_soon_count,
      COUNT(task.id) FILTER (WHERE task.work_state = 'WAITING')::integer AS waiting_task_count,
      COUNT(task.id) FILTER (WHERE task.work_state = 'BLOCKED')::integer AS blocked_task_count,
      COUNT(task.id) FILTER (WHERE task.status <> 'completed' AND public.task_dependency_blocked(task.id))::integer AS dependency_blocked_task_count,
      COUNT(task.id) FILTER (WHERE task.status <> 'completed' AND task.work_state = 'ACTIVE' AND NOT public.task_dependency_blocked(task.id))::integer AS actionable_task_count
    FROM scoped_projects project
    LEFT JOIN public.tasks task ON task.project_id = project.id AND task.archived_at IS NULL
    GROUP BY project.id
  ), todo_metrics AS (
    SELECT project.id AS project_id,
      COUNT(todo.id) FILTER (WHERE todo.status <> 'DONE')::integer AS open_todo_count,
      COUNT(todo.id) FILTER (WHERE todo.status <> 'DONE' AND todo.due_at < now())::integer AS overdue_todo_count
    FROM scoped_projects project
    LEFT JOIN public.project_todos todo ON todo.project_id = project.id
    GROUP BY project.id
  ), scored AS (
    SELECT project.*,
      COALESCE(task_metrics.task_count, 0) AS task_count,
      COALESCE(task_metrics.completed_task_count, 0) AS completed_task_count,
      COALESCE(task_metrics.overdue_task_count, 0) AS overdue_task_count,
      COALESCE(task_metrics.due_today_task_count, 0) AS due_today_task_count,
      COALESCE(task_metrics.critical_due_soon_count, 0) AS critical_due_soon_count,
      COALESCE(task_metrics.waiting_task_count, 0) AS waiting_task_count,
      COALESCE(task_metrics.blocked_task_count, 0) AS blocked_task_count,
      COALESCE(task_metrics.dependency_blocked_task_count, 0) AS dependency_blocked_task_count,
      COALESCE(task_metrics.actionable_task_count, 0) AS actionable_task_count,
      COALESCE(todo_metrics.open_todo_count, 0) AS open_todo_count,
      COALESCE(todo_metrics.overdue_todo_count, 0) AS overdue_todo_count,
      CASE WHEN project.event_date IS NULL THEN NULL ELSE project.event_date - CURRENT_DATE END AS event_countdown_days,
      CASE
        WHEN project.event_date IS NULL THEN 'NO_EVENT'
        WHEN project.event_date < CURRENT_DATE THEN 'PAST'
        WHEN project.event_date = CURRENT_DATE THEN 'TODAY'
        WHEN project.event_date = CURRENT_DATE + 1 THEN 'TOMORROW'
        ELSE 'UPCOMING'
      END AS event_status
    FROM scoped_projects project
    LEFT JOIN task_metrics ON task_metrics.project_id = project.id
    LEFT JOIN todo_metrics ON todo_metrics.project_id = project.id
  ), classified AS (
    SELECT scored.*,
      CASE
        WHEN event_date IS NOT NULL AND event_date <= CURRENT_DATE + 1
          AND (blocked_task_count >= 2 OR overdue_task_count >= 2 OR dependency_blocked_task_count >= 2 OR (critical_due_soon_count > 0 AND actionable_task_count > 0)) THEN 'CRITICAL'
        WHEN overdue_task_count >= 2 OR blocked_task_count >= 2 OR waiting_task_count >= 2 THEN 'AT_RISK'
        WHEN blocked_task_count > 0 OR waiting_task_count > 0 OR overdue_task_count > 0 OR dependency_blocked_task_count > 0 OR overdue_todo_count > 0
          OR (event_date IS NOT NULL AND event_date <= CURRENT_DATE + 3 AND actionable_task_count > 0) THEN 'AT_RISK'
        WHEN event_date IS NOT NULL AND event_date <= CURRENT_DATE + 7 AND actionable_task_count > 0 THEN 'NEEDS_ATTENTION'
        ELSE 'ON_TRACK'
      END AS health_state
    FROM scored
  )
  SELECT jsonb_build_object(
    'project_id', item.id,
    'project_name', item.project_name,
    'project_type', item.project_type,
    'project_status', item.project_status,
    'lifecycle_status', item.lifecycle_status,
    'priority', item.priority,
    'event_date', item.event_date,
    'start_date', item.start_date,
    'end_date', item.end_date,
    'event_countdown_days', item.event_countdown_days,
    'event_status', item.event_status,
    'client_name', item.client_name,
    'progress_percent', item.progress_percent,
    'health', item.health_state,
    'responsible_employee', CASE WHEN item.project_manager_id IS NULL THEN NULL ELSE jsonb_build_object('id', item.project_manager_id, 'full_name', item.owner_full_name, 'display_name', item.owner_display_name, 'display_name_ar', item.owner_display_name_ar, 'employee_id', item.owner_employee_id) END,
    'counts', jsonb_build_object(
      'tasks', item.task_count,
      'completed_tasks', item.completed_task_count,
      'actionable_tasks', item.actionable_task_count,
      'overdue_tasks', item.overdue_task_count,
      'due_today_tasks', item.due_today_task_count,
      'waiting_tasks', item.waiting_task_count,
      'blocked_tasks', item.blocked_task_count,
      'dependency_blocked_tasks', item.dependency_blocked_task_count,
      'open_todos', item.open_todo_count,
      'overdue_todos', item.overdue_todo_count
    ),
    'reason_codes', COALESCE(reason_codes.codes, '[]'::jsonb)
  )
  FROM classified item
  LEFT JOIN LATERAL (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('code', reason.code, 'count', reason.count) ORDER BY reason.rank), '[]'::jsonb) AS codes
    FROM (VALUES
      (1, CASE WHEN item.blocked_task_count > 0 THEN 'BLOCKED_TASKS'::text END, item.blocked_task_count),
      (2, CASE WHEN item.waiting_task_count > 0 THEN 'WAITING_TASKS'::text END, item.waiting_task_count),
      (3, CASE WHEN item.dependency_blocked_task_count > 0 THEN 'DEPENDENCY_RISK'::text END, item.dependency_blocked_task_count),
      (4, CASE WHEN item.overdue_task_count > 0 THEN 'OVERDUE_TASKS'::text END, item.overdue_task_count),
      (5, CASE WHEN item.overdue_todo_count > 0 THEN 'OVERDUE_TODOS'::text END, item.overdue_todo_count),
      (6, CASE WHEN item.event_status = 'TODAY' THEN 'EVENT_TODAY'::text WHEN item.event_status = 'TOMORROW' THEN 'EVENT_TOMORROW'::text WHEN item.event_status = 'UPCOMING' AND item.event_countdown_days <= 7 THEN 'EVENT_SOON'::text END, 1)
    ) reason(rank, code, count)
    WHERE reason.code IS NOT NULL
  ) reason_codes ON TRUE
  WHERE (NOT COALESCE(p_only_attention, false) OR item.health_state <> 'ON_TRACK')
    AND (p_upcoming_days IS NULL OR (item.event_date IS NOT NULL AND item.event_date >= CURRENT_DATE AND item.event_date <= CURRENT_DATE + GREATEST(p_upcoming_days, 0)))
  ORDER BY CASE item.health_state WHEN 'CRITICAL' THEN 1 WHEN 'AT_RISK' THEN 2 WHEN 'NEEDS_ATTENTION' THEN 3 ELSE 4 END,
    item.event_date NULLS LAST, item.overdue_task_count DESC, item.project_name
  LIMIT v_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_attention_needed(p_limit integer DEFAULT 20)
RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT item FROM public.list_project_command_center(p_limit, TRUE, NULL) item;
$$;

CREATE OR REPLACE FUNCTION public.list_upcoming_events(p_days integer DEFAULT 30, p_limit integer DEFAULT 20)
RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT item
  FROM public.list_project_command_center(p_limit, FALSE, p_days) item
  ORDER BY (item->>'event_date')::date ASC, item->>'project_name' ASC;
$$;

CREATE OR REPLACE FUNCTION public.get_project_health(p_project_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE result jsonb;
BEGIN
  SELECT item INTO result FROM public.list_project_command_center(1000, FALSE, NULL) item WHERE item->>'project_id' = p_project_id::text LIMIT 1;
  IF result IS NULL THEN RAISE EXCEPTION 'Project command center access denied' USING ERRCODE = '42501'; END IF;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_project_operational_summary(p_project_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE result jsonb;
BEGIN
  result := public.get_project_health(p_project_id);
  RETURN result || jsonb_build_object(
    'tasks', COALESCE((SELECT jsonb_agg(to_jsonb(task) - 'attachments' - 'description' ORDER BY task.due_date NULLS LAST, task.created_at DESC)
      FROM public.tasks task WHERE task.project_id = p_project_id AND task.archived_at IS NULL AND public.can_access_task(task.id, auth.uid())), '[]'::jsonb),
    'todos', COALESCE((SELECT jsonb_agg(to_jsonb(todo) ORDER BY todo.status DESC, todo.due_at ASC)
      FROM public.project_todos todo WHERE todo.project_id = p_project_id), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_project_command_center(integer, boolean, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_attention_needed(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_upcoming_events(integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_project_health(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_project_operational_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_project_command_center(integer, boolean, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_attention_needed(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_upcoming_events(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_project_health(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_project_operational_summary(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
