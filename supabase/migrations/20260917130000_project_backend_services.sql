-- Authoritative Project services for web and future native clients.
-- Project business rules remain independent from the Tasks Manager.
BEGIN;

CREATE OR REPLACE FUNCTION public.create_project_secure(p_project JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_project public.projects%ROWTYPE;
    v_project_manager UUID := NULLIF(p_project->>'project_manager_id', '')::UUID;
    v_assignees UUID[] := COALESCE(
        ARRAY(SELECT value::UUID FROM jsonb_array_elements_text(COALESCE(p_project->'assigned_people', '[]'::JSONB)) value),
        ARRAY[]::UUID[]
    );
    v_invalid UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    IF NULLIF(BTRIM(p_project->>'project_name'), '') IS NULL
       OR NULLIF(BTRIM(p_project->>'project_type'), '') IS NULL THEN
        RAISE EXCEPTION 'Project name and type are required' USING ERRCODE = '22023';
    END IF;
    IF v_project_manager IS NULL THEN v_project_manager := v_user; END IF;
    IF v_project_manager <> v_user AND NOT public.is_project_portfolio_admin(v_user) THEN
        RAISE EXCEPTION 'Only a portfolio administrator can create a project owned by another employee' USING ERRCODE = '42501';
    END IF;
    SELECT value INTO v_invalid
    FROM UNNEST(v_assignees) value
    WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = value AND p.is_active IS DISTINCT FROM FALSE)
    LIMIT 1;
    IF v_invalid IS NOT NULL THEN RAISE EXCEPTION 'Every project assignee must be active' USING ERRCODE = '22023'; END IF;

    INSERT INTO public.projects(
        project_name, project_type, description, assigned_people, project_category, project_tags,
        project_manager_id, created_by, lifecycle_status, health_status, priority, progress_percent,
        start_date, end_date, client_name, budget_amount, actual_cost
    ) VALUES (
        BTRIM(p_project->>'project_name'), BTRIM(p_project->>'project_type'), NULLIF(BTRIM(p_project->>'description'), ''),
        v_assignees, NULLIF(BTRIM(p_project->>'project_category'), ''),
        ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(p_project->'project_tags', '[]'::JSONB)) value),
        v_project_manager, v_user,
        COALESCE(NULLIF(UPPER(BTRIM(p_project->>'lifecycle_status')), ''), 'PLANNING'),
        COALESCE(NULLIF(UPPER(BTRIM(p_project->>'health_status')), ''), 'ON_TRACK'),
        COALESCE(NULLIF(UPPER(BTRIM(p_project->>'priority')), ''), 'MEDIUM'),
        COALESCE(NULLIF(p_project->>'progress_percent', '')::INTEGER, 0),
        NULLIF(p_project->>'start_date', '')::DATE, NULLIF(p_project->>'end_date', '')::DATE,
        NULLIF(BTRIM(p_project->>'client_name'), ''),
        CASE WHEN public.can_view_business_financials(v_user) THEN COALESCE(NULLIF(p_project->>'budget_amount', '')::NUMERIC, 0) ELSE 0 END,
        CASE WHEN public.can_view_business_financials(v_user) THEN COALESCE(NULLIF(p_project->>'actual_cost', '')::NUMERIC, 0) ELSE 0 END
    ) RETURNING * INTO v_project;
    RETURN to_jsonb(v_project) || jsonb_build_object(
        'project_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.project_amount) ELSE 'null'::JSONB END,
        'paid_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.paid_amount) ELSE 'null'::JSONB END,
        'budget_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.budget_amount) ELSE 'null'::JSONB END,
        'actual_cost', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.actual_cost) ELSE 'null'::JSONB END
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.update_project_secure(p_project_id UUID, p_changes JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_current public.projects%ROWTYPE;
    v_next public.projects%ROWTYPE;
    v_patch JSONB;
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
    -- Strip relationships, ownership, status transitions, audit columns, and unknown fields.
    v_patch := p_changes - ARRAY['id','created_at','updated_at','created_by','project_manager_id','assigned_people','deal_id','client_id','project_amount','paid_amount','project_status','source','order_employee_id','client_snapshot','equipment','lifecycle_status','last_update','last_update_at'];
    v_next := jsonb_populate_record(v_current, v_patch);
    UPDATE public.projects SET
        project_name=v_next.project_name, project_type=v_next.project_type, description=v_next.description,
        project_category=v_next.project_category, project_tags=v_next.project_tags, health_status=v_next.health_status,
        priority=v_next.priority, progress_percent=v_next.progress_percent, budget_amount=v_next.budget_amount,
        actual_cost=v_next.actual_cost, client_name=v_next.client_name, milestones=v_next.milestones, risks=v_next.risks,
        start_date=v_next.start_date, end_date=v_next.end_date, event_date=v_next.event_date,
        uninstallation_date=v_next.uninstallation_date, event_location=v_next.event_location,
        event_location_text=v_next.event_location_text, installation_type=v_next.installation_type,
        event_start_time=v_next.event_start_time, installation_time=v_next.installation_time,
        uninstallation_time=v_next.uninstallation_time, updated_at=NOW()
    WHERE id=p_project_id RETURNING * INTO v_next;
    RETURN to_jsonb(v_next) || jsonb_build_object(
        'project_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.project_amount) ELSE 'null'::JSONB END,
        'paid_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.paid_amount) ELSE 'null'::JSONB END,
        'budget_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.budget_amount) ELSE 'null'::JSONB END,
        'actual_cost', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.actual_cost) ELSE 'null'::JSONB END
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_project_secure(p_project_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_user UUID := auth.uid(); v_project public.projects%ROWTYPE;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id=p_project_id FOR UPDATE;
    IF NOT FOUND THEN RETURN FALSE; END IF;
    IF NOT (public.is_project_portfolio_admin(v_user) OR v_project.created_by=v_user OR v_project.project_manager_id=v_user) THEN
        RAISE EXCEPTION 'Only the project owner, manager, or administrator can delete this project' USING ERRCODE = '42501';
    END IF;
    DELETE FROM public.projects WHERE id=p_project_id;
    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_project_updates_secure(p_project_id UUID)
RETURNS SETOF JSONB
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT to_jsonb(update_row) || jsonb_build_object('author', CASE WHEN profile.id IS NULL THEN NULL ELSE jsonb_build_object('id', profile.id, 'full_name', profile.full_name, 'display_name_ar', profile.display_name_ar, 'emp_index', profile.emp_index) END)
    FROM public.project_updates update_row
    LEFT JOIN public.profiles profile ON profile.id=update_row.author_id
    WHERE update_row.project_id=p_project_id AND public.can_access_project(p_project_id, auth.uid())
    ORDER BY update_row.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.list_project_todos_secure(p_project_id UUID)
RETURNS SETOF JSONB
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    SELECT to_jsonb(todo_row)
    FROM public.project_todos todo_row
    WHERE todo_row.project_id=p_project_id AND public.can_access_project(p_project_id, auth.uid())
    ORDER BY todo_row.status DESC, todo_row.due_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.get_project_detail_secure(p_project_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_user UUID := auth.uid(); v_project public.projects%ROWTYPE; v_can_financial BOOLEAN; v_project_json JSONB;
BEGIN
    IF v_user IS NULL OR NOT public.can_access_project(p_project_id, v_user) THEN RAISE EXCEPTION 'Project not found or access denied' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id=p_project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE='P0002'; END IF;
    v_can_financial := public.can_view_business_financials(v_user);
    v_project_json := to_jsonb(v_project) || jsonb_build_object(
        'project_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.project_amount) ELSE 'null'::JSONB END,
        'paid_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.paid_amount) ELSE 'null'::JSONB END,
        'budget_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.budget_amount) ELSE 'null'::JSONB END,
        'actual_cost', CASE WHEN v_can_financial THEN to_jsonb(v_project.actual_cost) ELSE 'null'::JSONB END
    );
    RETURN jsonb_build_object(
        'project', v_project_json,
        'updates', COALESCE((SELECT jsonb_agg(item) FROM public.list_project_updates_secure(p_project_id) item), '[]'::JSONB),
        'todos', COALESCE((SELECT jsonb_agg(item) FROM public.list_project_todos_secure(p_project_id) item), '[]'::JSONB),
        'attachments', COALESCE((SELECT jsonb_agg(to_jsonb(item)) FROM public.list_project_shared_attachments(p_project_id) item), '[]'::JSONB)
    );
END;
$$;

-- Direct Project table mutations are no longer part of the client contract.
REVOKE ALL ON public.projects FROM authenticated;
REVOKE ALL ON public.project_updates FROM authenticated;
REVOKE ALL ON public.project_todos FROM authenticated;
GRANT EXECUTE ON FUNCTION public.create_project_secure(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_project_secure(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_project_secure(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_project_updates_secure(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_project_todos_secure(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_project_detail_secure(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_project_secure(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_project_secure(UUID, JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_project_secure(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_project_updates_secure(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_project_todos_secure(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_project_detail_secure(UUID) FROM PUBLIC, anon;
NOTIFY pgrst, 'reload schema';
COMMIT;
