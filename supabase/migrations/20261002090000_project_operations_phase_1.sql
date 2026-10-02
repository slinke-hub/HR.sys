-- Project Operations Phase 1: server-authoritative progress/health and closure readiness.
-- No tables, columns, task permissions, or Project access rules are changed.
BEGIN;

CREATE OR REPLACE FUNCTION public.project_operational_snapshot(
  p_project_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  project_row public.projects%ROWTYPE;
  owner_profile public.profiles%ROWTYPE;
  task_count integer := 0;
  completed_task_count integer := 0;
  overdue_task_count integer := 0;
  due_today_task_count integer := 0;
  critical_due_soon_count integer := 0;
  waiting_task_count integer := 0;
  blocked_task_count integer := 0;
  dependency_blocked_task_count integer := 0;
  actionable_task_count integer := 0;
  open_todo_count integer := 0;
  overdue_todo_count integer := 0;
  progress integer := 0;
  event_days integer;
  event_state text;
  health_state text;
  reason_codes jsonb := '[]'::jsonb;
BEGIN
  IF p_user_id IS NULL OR p_user_id IS DISTINCT FROM auth.uid()
     OR NOT public.can_access_project(p_project_id, p_user_id) THEN
    RAISE EXCEPTION 'Project not found or access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO project_row FROM public.projects WHERE id = p_project_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE = 'P0002'; END IF;

  -- Project members receive one shared Project-level operational aggregate.
  -- Task rows/details remain independently gated by can_access_task() below.
  SELECT COUNT(*)::integer,
    COUNT(*) FILTER (WHERE task.status = 'completed')::integer,
    COUNT(*) FILTER (WHERE task.status <> 'completed' AND task.due_date < CURRENT_DATE)::integer,
    COUNT(*) FILTER (WHERE task.status <> 'completed' AND task.due_date = CURRENT_DATE)::integer,
    COUNT(*) FILTER (WHERE task.status <> 'completed' AND task.due_date >= CURRENT_DATE AND task.due_date <= CURRENT_DATE + 3 AND LOWER(COALESCE(task.priority, '')) IN ('high', 'urgent', 'critical'))::integer,
    COUNT(*) FILTER (WHERE task.work_state = 'WAITING')::integer,
    COUNT(*) FILTER (WHERE task.work_state = 'BLOCKED')::integer,
    COUNT(*) FILTER (WHERE task.status <> 'completed' AND public.task_dependency_blocked(task.id))::integer,
    COUNT(*) FILTER (WHERE task.status <> 'completed' AND task.work_state = 'ACTIVE' AND NOT public.task_dependency_blocked(task.id))::integer
  INTO task_count, completed_task_count, overdue_task_count, due_today_task_count,
    critical_due_soon_count, waiting_task_count, blocked_task_count,
    dependency_blocked_task_count, actionable_task_count
  FROM public.tasks task
  WHERE task.project_id = p_project_id
    AND task.archived_at IS NULL;

  -- Progress includes all non-archived Project Tasks. Only the authoritative
  -- completed status counts as complete; cancelled Tasks remain incomplete.
  -- A Project with no non-archived Tasks has deterministic 0% progress.
  IF task_count > 0 THEN
    progress := ROUND(100.0 * completed_task_count / task_count)::integer;
  END IF;

  SELECT COUNT(*) FILTER (WHERE todo.status <> 'DONE')::integer,
    COUNT(*) FILTER (WHERE todo.status <> 'DONE' AND todo.due_at < now())::integer
  INTO open_todo_count, overdue_todo_count
  FROM public.project_todos todo
  WHERE todo.project_id = p_project_id;

  event_days := CASE WHEN project_row.event_date IS NULL THEN NULL ELSE project_row.event_date - CURRENT_DATE END;
  event_state := CASE
    WHEN project_row.event_date IS NULL THEN 'NO_EVENT'
    WHEN event_days < 0 THEN 'PAST'
    WHEN event_days = 0 THEN 'TODAY'
    WHEN event_days = 1 THEN 'TOMORROW'
    ELSE 'UPCOMING'
  END;

  -- Keep the reviewed Phase C thresholds and reason ordering unchanged.
  health_state := CASE
    WHEN project_row.event_date IS NOT NULL AND event_days <= 1
      AND (blocked_task_count >= 2 OR overdue_task_count >= 2 OR dependency_blocked_task_count >= 2 OR (critical_due_soon_count > 0 AND actionable_task_count > 0)) THEN 'CRITICAL'
    WHEN overdue_task_count >= 2 OR blocked_task_count >= 2 OR waiting_task_count >= 2 THEN 'AT_RISK'
    WHEN blocked_task_count > 0 OR waiting_task_count > 0 OR overdue_task_count > 0 OR dependency_blocked_task_count > 0 OR overdue_todo_count > 0
      OR (project_row.event_date IS NOT NULL AND event_days <= 3 AND actionable_task_count > 0) THEN 'AT_RISK'
    WHEN project_row.event_date IS NOT NULL AND event_days <= 7 AND actionable_task_count > 0 THEN 'NEEDS_ATTENTION'
    ELSE 'ON_TRACK'
  END;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('code', reason.code, 'count', reason.count) ORDER BY reason.rank), '[]'::jsonb)
  INTO reason_codes
  FROM (VALUES
    (1, CASE WHEN blocked_task_count > 0 THEN 'BLOCKED_TASKS'::text END, blocked_task_count),
    (2, CASE WHEN waiting_task_count > 0 THEN 'WAITING_TASKS'::text END, waiting_task_count),
    (3, CASE WHEN dependency_blocked_task_count > 0 THEN 'DEPENDENCY_RISK'::text END, dependency_blocked_task_count),
    (4, CASE WHEN overdue_task_count > 0 THEN 'OVERDUE_TASKS'::text END, overdue_task_count),
    (5, CASE WHEN overdue_todo_count > 0 THEN 'OVERDUE_TODOS'::text END, overdue_todo_count),
    (6, CASE WHEN event_state = 'TODAY' THEN 'EVENT_TODAY'::text WHEN event_state = 'TOMORROW' THEN 'EVENT_TOMORROW'::text WHEN event_state = 'UPCOMING' AND event_days <= 7 THEN 'EVENT_SOON'::text END, 1)
  ) reason(rank, code, count)
  WHERE reason.code IS NOT NULL;

  IF public.is_project_portfolio_admin(p_user_id)
     OR project_row.created_by = p_user_id OR project_row.project_manager_id = p_user_id THEN
    SELECT * INTO owner_profile FROM public.profiles WHERE id = project_row.project_manager_id;
  END IF;

  RETURN jsonb_build_object(
    'project_id', project_row.id,
    'project_name', project_row.project_name,
    'project_type', project_row.project_type,
    'project_status', project_row.project_status,
    'lifecycle_status', project_row.lifecycle_status,
    'priority', project_row.priority,
    'event_date', project_row.event_date,
    'start_date', project_row.start_date,
    'end_date', project_row.end_date,
    'event_countdown_days', event_days,
    'event_status', event_state,
    'client_name', project_row.client_name,
    'progress_percent', progress,
    'health', health_state,
    'health_status', health_state,
    'responsible_employee', CASE WHEN owner_profile.id IS NULL THEN NULL ELSE jsonb_build_object('id', owner_profile.id, 'full_name', owner_profile.full_name, 'display_name', owner_profile.display_name, 'display_name_ar', owner_profile.display_name_ar, 'employee_id', owner_profile.employee_id) END,
    'counts', jsonb_build_object(
      'tasks', task_count, 'completed_tasks', completed_task_count,
      'actionable_tasks', actionable_task_count, 'overdue_tasks', overdue_task_count,
      'due_today_tasks', due_today_task_count, 'waiting_tasks', waiting_task_count,
      'blocked_tasks', blocked_task_count, 'dependency_blocked_tasks', dependency_blocked_task_count,
      'open_todos', open_todo_count, 'overdue_todos', overdue_todo_count
    ),
    'reason_codes', reason_codes
  );
END;
$$;

-- The Client detail façade embeds Project summaries. Preserve its reviewed
-- authorization/DTO behavior while replacing its stored operational fields.
DO $project_ops_client_facade$
BEGIN
  IF to_regprocedure('public.get_crm_client_secure_project_ops_base(uuid)') IS NULL THEN
    IF to_regprocedure('public.get_crm_client_secure(uuid)') IS NULL THEN
      RAISE EXCEPTION 'Expected secure Client detail façade was not found';
    END IF;
    EXECUTE 'ALTER FUNCTION public.get_crm_client_secure(uuid) RENAME TO get_crm_client_secure_project_ops_base';
  END IF;
END;
$project_ops_client_facade$;
REVOKE ALL ON FUNCTION public.get_crm_client_secure_project_ops_base(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_crm_client_secure(p_client_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_result jsonb;
  v_has_financial_access boolean := public.can_view_business_financials(auth.uid());
BEGIN
  -- The original secure façade performs CRM authorization and client lookup.
  v_result := public.get_crm_client_secure_project_ops_base(p_client_id);
  RETURN v_result || jsonb_build_object('projects', COALESCE((
    WITH accessible_projects AS MATERIALIZED (
      SELECT project.* FROM public.projects project
      WHERE project.client_id = p_client_id
        AND public.can_access_project(project.id, auth.uid())
    )
    SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', project.id,
      'project_name', project.project_name,
      'project_type', project.project_type,
      'project_status', project.project_status,
      'lifecycle_status', project.lifecycle_status,
      'health_status', snapshot.item->>'health',
      'priority', project.priority,
      'progress_percent', (snapshot.item->>'progress_percent')::integer,
      'reason_codes', snapshot.item->'reason_codes',
      'event_date', project.event_date,
      'end_date', project.end_date,
      'created_at', project.created_at,
      'deal_id', project.deal_id,
      'project_amount', CASE WHEN v_has_financial_access THEN project.project_amount END,
      'paid_amount', CASE WHEN v_has_financial_access THEN project.paid_amount END,
      'budget_amount', CASE WHEN v_has_financial_access THEN project.budget_amount END,
      'actual_cost', CASE WHEN v_has_financial_access THEN project.actual_cost END
    )) ORDER BY project.created_at DESC)
    FROM accessible_projects project
    CROSS JOIN LATERAL (SELECT public.project_operational_snapshot(project.id, auth.uid()) AS item) snapshot
  ), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.create_project_secure(p_project jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_project public.projects%ROWTYPE;
  v_snapshot jsonb;
  v_project_manager uuid := NULLIF(p_project->>'project_manager_id', '')::uuid;
  v_assignees uuid[] := COALESCE(ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(p_project->'assigned_people', '[]'::jsonb)) value), ARRAY[]::uuid[]);
  v_invalid uuid;
  v_lifecycle_status text := COALESCE(NULLIF(UPPER(BTRIM(p_project->>'lifecycle_status')), ''), 'PLANNING');
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF NULLIF(BTRIM(p_project->>'project_name'), '') IS NULL OR NULLIF(BTRIM(p_project->>'project_type'), '') IS NULL THEN
    RAISE EXCEPTION 'Project name and type are required' USING ERRCODE = '22023';
  END IF;
  IF v_lifecycle_status NOT IN ('PLANNING', 'ACTIVE', 'ON_HOLD') THEN
    RAISE EXCEPTION 'Projects must be created in a non-terminal lifecycle state' USING ERRCODE = '22023';
  END IF;
  IF v_project_manager IS NULL THEN v_project_manager := v_user; END IF;
  IF v_project_manager <> v_user AND NOT public.is_project_portfolio_admin(v_user) THEN
    RAISE EXCEPTION 'Only a portfolio administrator can create a project owned by another employee' USING ERRCODE = '42501';
  END IF;
  SELECT value INTO v_invalid FROM UNNEST(v_assignees) value
    WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = value AND p.is_active IS DISTINCT FROM FALSE) LIMIT 1;
  IF v_invalid IS NOT NULL THEN RAISE EXCEPTION 'Every project assignee must be active' USING ERRCODE = '22023'; END IF;
  INSERT INTO public.projects(
    project_name, project_type, description, assigned_people, project_category, project_tags,
    project_manager_id, created_by, lifecycle_status, health_status, priority, progress_percent,
    start_date, end_date, event_date, client_name, budget_amount, actual_cost
  ) VALUES (
    BTRIM(p_project->>'project_name'), BTRIM(p_project->>'project_type'), NULLIF(BTRIM(p_project->>'description'), ''),
    v_assignees, NULLIF(BTRIM(p_project->>'project_category'), ''),
    ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(p_project->'project_tags', '[]'::jsonb)) value),
    v_project_manager, v_user,
    v_lifecycle_status,
    'ON_TRACK', COALESCE(NULLIF(UPPER(BTRIM(p_project->>'priority')), ''), 'MEDIUM'), 0,
    NULLIF(p_project->>'start_date', '')::date, NULLIF(p_project->>'end_date', '')::date,
    NULLIF(p_project->>'event_date', '')::date,
    NULLIF(BTRIM(p_project->>'client_name'), ''),
    CASE WHEN public.can_view_business_financials(v_user) THEN COALESCE(NULLIF(p_project->>'budget_amount', '')::numeric, 0) ELSE 0 END,
    CASE WHEN public.can_view_business_financials(v_user) THEN COALESCE(NULLIF(p_project->>'actual_cost', '')::numeric, 0) ELSE 0 END
  ) RETURNING * INTO v_project;
  v_snapshot := public.project_operational_snapshot(v_project.id, v_user);
  RETURN to_jsonb(v_project) || jsonb_build_object(
    'project_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.project_amount) ELSE 'null'::jsonb END,
    'paid_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.paid_amount) ELSE 'null'::jsonb END,
    'budget_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.budget_amount) ELSE 'null'::jsonb END,
    'actual_cost', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.actual_cost) ELSE 'null'::jsonb END,
    'progress_percent', (v_snapshot->>'progress_percent')::integer,
    'health_status', v_snapshot->>'health',
    'reason_codes', v_snapshot->'reason_codes'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.update_project_secure(p_project_id uuid, p_changes jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_current public.projects%ROWTYPE;
  v_next public.projects%ROWTYPE;
  v_patch jsonb;
  v_snapshot jsonb;
BEGIN
  IF v_user IS NULL OR NOT public.can_access_project(p_project_id, v_user) THEN RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_current FROM public.projects WHERE id = p_project_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE = 'P0002'; END IF;
  IF NOT (public.is_project_portfolio_admin(v_user) OR v_current.created_by = v_user OR v_current.project_manager_id = v_user) THEN
    RAISE EXCEPTION 'Only the project owner or manager can update project details' USING ERRCODE = '42501';
  END IF;
  IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'object' THEN RAISE EXCEPTION 'Project changes must be an object' USING ERRCODE = '22023'; END IF;
  IF (p_changes ? 'budget_amount' OR p_changes ? 'actual_cost') AND NOT public.can_view_business_financials(v_user) THEN
    RAISE EXCEPTION 'Financial project fields are restricted' USING ERRCODE = '42501';
  END IF;
  v_patch := p_changes - ARRAY['id','created_at','updated_at','created_by','project_manager_id','assigned_people','deal_id','client_id','project_amount','paid_amount','project_status','source','order_employee_id','client_snapshot','equipment','lifecycle_status','health_status','progress_percent','last_update','last_update_at'];
  v_next := jsonb_populate_record(v_current, v_patch);
  UPDATE public.projects SET
    project_name=v_next.project_name, project_type=v_next.project_type, description=v_next.description,
    project_category=v_next.project_category, project_tags=v_next.project_tags,
    priority=v_next.priority, budget_amount=v_next.budget_amount,
    actual_cost=v_next.actual_cost, client_name=v_next.client_name, milestones=v_next.milestones, risks=v_next.risks,
    start_date=v_next.start_date, end_date=v_next.end_date, event_date=v_next.event_date,
    uninstallation_date=v_next.uninstallation_date, event_location=v_next.event_location,
    event_location_text=v_next.event_location_text, installation_type=v_next.installation_type,
    event_start_time=v_next.event_start_time, installation_time=v_next.installation_time,
    uninstallation_time=v_next.uninstallation_time, updated_at=NOW()
  WHERE id=p_project_id RETURNING * INTO v_next;
  v_snapshot := public.project_operational_snapshot(p_project_id, v_user);
  RETURN to_jsonb(v_next) || jsonb_build_object(
    'project_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.project_amount) ELSE 'null'::jsonb END,
    'paid_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.paid_amount) ELSE 'null'::jsonb END,
    'budget_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.budget_amount) ELSE 'null'::jsonb END,
    'actual_cost', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.actual_cost) ELSE 'null'::jsonb END,
    'progress_percent', (v_snapshot->>'progress_percent')::integer,
    'health_status', v_snapshot->>'health',
    'reason_codes', v_snapshot->'reason_codes'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_accessible_projects_secure()
RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH accessible_projects AS MATERIALIZED (
    SELECT project.* FROM public.projects project
    WHERE auth.uid() IS NOT NULL AND public.can_access_project(project.id, auth.uid())
  )
  SELECT to_jsonb(project) || jsonb_build_object(
    'project_amount', CASE WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(project.project_amount) ELSE 'null'::jsonb END,
    'paid_amount', CASE WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(project.paid_amount) ELSE 'null'::jsonb END,
    'budget_amount', CASE WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(project.budget_amount) ELSE 'null'::jsonb END,
    'actual_cost', CASE WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(project.actual_cost) ELSE 'null'::jsonb END,
    'payment_ready', COALESCE(project.project_amount, 0) <= 0 OR COALESCE(project.paid_amount, 0) >= COALESCE(project.project_amount, 0),
    'crm_clients', CASE WHEN client.id IS NULL THEN NULL ELSE jsonb_build_object('name', client.name, 'company', client.company) END,
    'progress_percent', (snapshot.item->>'progress_percent')::integer,
    'health_status', snapshot.item->>'health',
    'reason_codes', snapshot.item->'reason_codes'
  )
  FROM accessible_projects project
  CROSS JOIN LATERAL (SELECT public.project_operational_snapshot(project.id, auth.uid()) AS item) snapshot
  LEFT JOIN public.crm_clients client ON client.id = project.client_id
  ORDER BY project.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_project_detail_secure(p_project_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_project public.projects%ROWTYPE;
  v_can_financial boolean;
  v_snapshot jsonb;
  v_project_json jsonb;
BEGIN
  IF v_user IS NULL OR NOT public.can_access_project(p_project_id, v_user) THEN RAISE EXCEPTION 'Project not found or access denied' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE = 'P0002'; END IF;
  v_can_financial := public.can_view_business_financials(v_user);
  v_snapshot := public.project_operational_snapshot(p_project_id, v_user);
  v_project_json := to_jsonb(v_project) || jsonb_build_object(
    'project_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.project_amount) ELSE 'null'::jsonb END,
    'paid_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.paid_amount) ELSE 'null'::jsonb END,
    'budget_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.budget_amount) ELSE 'null'::jsonb END,
    'actual_cost', CASE WHEN v_can_financial THEN to_jsonb(v_project.actual_cost) ELSE 'null'::jsonb END,
    'progress_percent', (v_snapshot->>'progress_percent')::integer,
    'health_status', v_snapshot->>'health',
    'reason_codes', v_snapshot->'reason_codes'
  );
  RETURN jsonb_build_object(
    'project', v_project_json,
    'updates', COALESCE((SELECT jsonb_agg(item) FROM public.list_project_updates_secure(p_project_id) item), '[]'::jsonb),
    'todos', COALESCE((SELECT jsonb_agg(item) FROM public.list_project_todos_secure(p_project_id) item), '[]'::jsonb),
    'attachments', COALESCE((SELECT jsonb_agg(to_jsonb(item)) FROM public.list_project_shared_attachments(p_project_id) item), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_project_command_center(
  p_limit integer DEFAULT 50,
  p_only_attention boolean DEFAULT false,
  p_upcoming_days integer DEFAULT NULL
)
RETURNS SETOF jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 1000);
BEGIN
  IF v_user IS NULL OR NOT public.is_project_portfolio_admin(v_user) THEN
    RAISE EXCEPTION 'Project command center access denied' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  WITH accessible_projects AS MATERIALIZED (
    SELECT project.* FROM public.projects project
    WHERE project.lifecycle_status <> 'CANCELLED' AND public.can_access_project(project.id, v_user)
      AND (p_upcoming_days IS NULL OR (project.event_date IS NOT NULL AND project.event_date >= CURRENT_DATE AND project.event_date <= CURRENT_DATE + GREATEST(p_upcoming_days, 0)))
  )
  SELECT snapshot.item
  FROM accessible_projects project
  CROSS JOIN LATERAL (SELECT public.project_operational_snapshot(project.id, v_user) AS item) snapshot
  WHERE NOT COALESCE(p_only_attention, false) OR snapshot.item->>'health' <> 'ON_TRACK'
  ORDER BY CASE snapshot.item->>'health' WHEN 'CRITICAL' THEN 1 WHEN 'AT_RISK' THEN 2 WHEN 'NEEDS_ATTENTION' THEN 3 ELSE 4 END,
    project.event_date NULLS LAST,
    COALESCE((snapshot.item->'counts'->>'overdue_tasks')::integer, 0) DESC,
    project.project_name
  LIMIT v_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_project_operational_summary(p_project_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_user uuid := auth.uid(); v_snapshot jsonb;
BEGIN
  IF v_user IS NULL OR NOT public.can_access_project(p_project_id, v_user) THEN
    RAISE EXCEPTION 'Project not found or access denied' USING ERRCODE = '42501';
  END IF;
  v_snapshot := public.project_operational_snapshot(p_project_id, v_user);
  RETURN v_snapshot || jsonb_build_object(
    'tasks', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', task.id, 'title', task.title, 'status', task.status, 'work_state', task.work_state,
        'priority', task.priority, 'due_date', task.due_date
      ) ORDER BY task.due_date NULLS LAST, task.created_at DESC)
      FROM public.tasks task
      WHERE task.project_id = p_project_id AND task.archived_at IS NULL
        AND public.can_access_task(task.id, v_user)
    ), '[]'::jsonb),
    'todos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', todo.id, 'title', todo.title, 'status', todo.status, 'due_at', todo.due_at) ORDER BY todo.status DESC, todo.due_at ASC)
      FROM public.project_todos todo WHERE todo.project_id = p_project_id
    ), '[]'::jsonb),
    'financials_included', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_project_health(p_project_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
    RAISE EXCEPTION 'Project not found or access denied' USING ERRCODE = '42501';
  END IF;
  RETURN public.project_operational_snapshot(p_project_id, auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.get_project_completion_readiness(p_project_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  project_row public.projects%ROWTYPE;
  total_tasks integer := 0;
  completed_tasks integer := 0;
  incomplete_tasks integer := 0;
  blocked_tasks integer := 0;
  waiting_tasks integer := 0;
  dependency_blocked_tasks integer := 0;
  reasons jsonb := '[]'::jsonb;
BEGIN
  IF v_user IS NULL OR NOT public.can_access_project(p_project_id, v_user) THEN
    RAISE EXCEPTION 'Project not found or access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO project_row FROM public.projects WHERE id = p_project_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE = 'P0002'; END IF;
  IF NOT (public.is_project_portfolio_admin(v_user) OR project_row.created_by = v_user OR project_row.project_manager_id = v_user) THEN
    RAISE EXCEPTION 'Only the project owner, manager, or portfolio administrator can check completion readiness' USING ERRCODE = '42501';
  END IF;

  -- Closure is leadership-only; aggregate counts are project-scoped and no Task
  -- rows, titles, assignees, or unrelated Project data are returned.
  SELECT COUNT(*)::integer,
    COUNT(*) FILTER (WHERE task.status = 'completed')::integer,
    COUNT(*) FILTER (WHERE task.status IS DISTINCT FROM 'completed')::integer,
    COUNT(*) FILTER (WHERE task.work_state = 'BLOCKED' AND task.status IS DISTINCT FROM 'completed')::integer,
    COUNT(*) FILTER (WHERE task.work_state = 'WAITING' AND task.status IS DISTINCT FROM 'completed')::integer,
    COUNT(*) FILTER (WHERE task.status IS DISTINCT FROM 'completed' AND public.task_dependency_blocked(task.id))::integer
  INTO total_tasks, completed_tasks, incomplete_tasks, blocked_tasks, waiting_tasks, dependency_blocked_tasks
  FROM public.tasks task
  WHERE task.project_id = p_project_id AND task.archived_at IS NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('code', reason.code, 'count', reason.count) ORDER BY reason.rank), '[]'::jsonb)
  INTO reasons
  FROM (VALUES
    (1, CASE WHEN total_tasks = 0 THEN 'NO_TASKS'::text END, CASE WHEN total_tasks = 0 THEN 1 ELSE 0 END),
    (2, CASE WHEN incomplete_tasks > 0 THEN 'INCOMPLETE_TASKS'::text END, incomplete_tasks),
    (3, CASE WHEN blocked_tasks > 0 THEN 'BLOCKED_TASKS'::text END, blocked_tasks),
    (4, CASE WHEN waiting_tasks > 0 THEN 'WAITING_TASKS'::text END, waiting_tasks),
    (5, CASE WHEN dependency_blocked_tasks > 0 THEN 'UNRESOLVED_DEPENDENCY_CHAIN'::text END, dependency_blocked_tasks)
  ) reason(rank, code, count)
  WHERE reason.code IS NOT NULL;

  RETURN jsonb_build_object(
    'project_id', p_project_id,
    'ready', total_tasks > 0 AND incomplete_tasks = 0 AND blocked_tasks = 0 AND waiting_tasks = 0 AND dependency_blocked_tasks = 0,
    'zero_task_project_closure_ready', false,
    'counts', jsonb_build_object('tasks', total_tasks, 'completed_tasks', completed_tasks, 'incomplete_tasks', incomplete_tasks,
      'blocked_tasks', blocked_tasks, 'waiting_tasks', waiting_tasks, 'dependency_blocked_tasks', dependency_blocked_tasks),
    'reason_codes', reasons,
    'project_todos_enforced', false,
    'project_todos_note', 'Project To-Dos have no required/optional marker and are not part of closure readiness.'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.change_project_status(p_project_id uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_project public.projects%ROWTYPE;
  v_status text := UPPER(BTRIM(COALESCE(p_status, '')));
  v_readiness jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
    RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_project_portfolio_admin(auth.uid()) THEN
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
    IF NOT FOUND OR (v_project.created_by <> auth.uid() AND v_project.project_manager_id <> auth.uid()) THEN
      RAISE EXCEPTION 'Only the project owner or manager can change project status' USING ERRCODE = '42501';
    END IF;
  ELSE
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE = 'P0002'; END IF;
  END IF;
  IF v_status NOT IN ('PLANNING','ACTIVE','ON_HOLD','COMPLETED','CANCELLED') THEN
    RAISE EXCEPTION 'Invalid project status' USING ERRCODE = '22023';
  END IF;
  IF v_status = 'COMPLETED' THEN
    v_readiness := public.get_project_completion_readiness(p_project_id);
    IF v_readiness->'ready' = 'false'::jsonb THEN
      RETURN jsonb_build_object('project_id', p_project_id, 'status', v_project.lifecycle_status, 'changed', false, 'completion_readiness', v_readiness);
    END IF;
  END IF;
  UPDATE public.projects
     SET lifecycle_status = v_status,
         project_status = CASE v_status WHEN 'PLANNING' THEN 'Planning' WHEN 'ACTIVE' THEN 'In Progress' WHEN 'ON_HOLD' THEN 'On Hold' WHEN 'COMPLETED' THEN 'Completed' WHEN 'CANCELLED' THEN 'Cancelled' END,
         updated_at = NOW()
   WHERE id = p_project_id;
  INSERT INTO public.project_updates(project_id, author_id, update_type, summary)
  VALUES (p_project_id, auth.uid(), 'UPDATE', format('Project status changed to %s', v_status));
  RETURN jsonb_build_object('project_id', p_project_id, 'status', v_status, 'actor_id', auth.uid(), 'changed', true,
    'completion_readiness', CASE WHEN v_status = 'COMPLETED' THEN v_readiness ELSE NULL END);
END;
$$;

REVOKE ALL ON FUNCTION public.project_operational_snapshot(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_crm_client_secure(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_crm_client_secure(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.list_accessible_projects_secure() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_project_detail_secure(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_project_operational_summary(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_project_health(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_project_completion_readiness(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.change_project_status(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_accessible_projects_secure() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_project_detail_secure(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_project_operational_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_project_health(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_project_completion_readiness(uuid) TO authenticated;

-- Retire the legacy Deal-to-Project path that accepts caller-chosen status.
-- The reviewed v2 workflow remains the supported Deal conversion path.
REVOKE ALL ON FUNCTION public.create_project_from_won_deal(uuid, date, date, date, date, text, numeric, numeric, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.change_project_status(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
