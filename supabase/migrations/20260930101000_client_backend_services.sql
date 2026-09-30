-- Reviewed production migration generated from the verified service artifact.
-- Source artifact: client_backend_services.sql
-- No environment reference, test identity, synthetic fixture, or cleanup harness is included.
-- reviewed production authoritative Client service boundary.
-- The existing crm_clients table is preserved; clients use DTO/RPC operations
-- while direct authenticated table writes are revoked.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_client_dto(p_client public.crm_clients)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'id', p_client.id,
    'name', p_client.name,
    'email', p_client.email,
    'phone', p_client.phone,
    'company', p_client.company,
    'status', p_client.status,
    'created_at', p_client.created_at,
    'assigned_to', p_client.assigned_to,
    'assigned_employee', (
      SELECT jsonb_strip_nulls(jsonb_build_object(
        'id', profile.id,
        'full_name', profile.full_name,
        'display_name_ar', profile.display_name_ar,
        'emp_index', profile.emp_index
      ))
      FROM public.profiles profile
      WHERE profile.id = p_client.assigned_to
    )
  ));
$$;

CREATE OR REPLACE FUNCTION public.list_crm_clients_secure(p_search text DEFAULT NULL)
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT public.crm_client_dto(client)
  FROM public.crm_clients client
  WHERE auth.uid() IS NOT NULL
    AND public.can_access_crm(auth.uid())
    AND (
      NULLIF(BTRIM(COALESCE(p_search, '')), '') IS NULL
      OR concat_ws(' ', client.name, client.company, client.email, client.phone)
         ILIKE '%' || BTRIM(p_search) || '%'
    )
  ORDER BY client.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_crm_client_secure(p_client_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_client public.crm_clients%ROWTYPE;
  v_has_financial_access boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_client FROM public.crm_clients WHERE id = p_client_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Client not found or access denied' USING ERRCODE = '42501';
  END IF;

  v_has_financial_access := public.can_view_business_financials(auth.uid());

  RETURN jsonb_build_object(
    'client', public.crm_client_dto(v_client),
    'deals', COALESCE((
      SELECT jsonb_agg(deal_row ORDER BY deal_row->>'created_at' DESC)
      FROM (
        SELECT jsonb_strip_nulls(
          jsonb_build_object(
            'id', deal.id,
            'title', deal.title,
            'stage', deal.stage,
            'workflow_status', deal.workflow_status,
            'assigned_to', deal.assigned_to,
            'created_at', deal.created_at,
            'event_type', deal.event_type,
            'first_contact_date', deal.first_contact_date
          ) || CASE WHEN v_has_financial_access
            THEN jsonb_build_object('amount', deal.amount)
            ELSE '{}'::jsonb END
        ) AS deal_row
        FROM public.crm_deals deal
        WHERE deal.client_id = v_client.id
      ) related_deals
    ), '[]'::jsonb),
    'projects', COALESCE((
      SELECT jsonb_agg(project_row ORDER BY project_row->>'created_at' DESC)
      FROM (
        SELECT jsonb_strip_nulls(
          jsonb_build_object(
            'id', project.id,
            'project_name', project.project_name,
            'project_type', project.project_type,
            'project_status', project.project_status,
            'lifecycle_status', project.lifecycle_status,
            'health_status', project.health_status,
            'priority', project.priority,
            'progress_percent', project.progress_percent,
            'event_date', project.event_date,
            'end_date', project.end_date,
            'created_at', project.created_at,
            'deal_id', project.deal_id
          ) || CASE WHEN v_has_financial_access
            THEN jsonb_build_object(
              'project_amount', project.project_amount,
              'paid_amount', project.paid_amount,
              'budget_amount', project.budget_amount,
              'actual_cost', project.actual_cost
            )
            ELSE '{}'::jsonb END
        ) AS project_row
        FROM public.projects project
        WHERE project.client_id = v_client.id
          AND public.can_access_project(project.id, auth.uid())
      ) related_projects
    ), '[]'::jsonb),
    'tasks', COALESCE((
      SELECT jsonb_agg(task_row ORDER BY task_row->>'created_at' DESC)
      FROM (
        SELECT jsonb_build_object(
          'id', task.id,
          'title', task.title,
          'status', task.status,
          'priority', task.priority,
          'due_date', task.due_date,
          'project_id', task.project_id,
          'crm_deal_id', task.crm_deal_id,
          'assignee_id', task.assignee_id,
          'assignee_ids', task.assignee_ids,
          'created_at', task.created_at,
          'updated_at', task.updated_at
        ) AS task_row
        FROM public.tasks task
        LEFT JOIN public.projects project ON project.id = task.project_id
        LEFT JOIN public.crm_deals deal ON deal.id = task.crm_deal_id
        WHERE (
          (project.client_id = v_client.id AND public.can_access_project(project.id, auth.uid()))
          OR (deal.client_id = v_client.id AND public.can_access_crm(auth.uid()))
        )
      ) related_tasks
    ), '[]'::jsonb),
    'activity', COALESCE((
      SELECT jsonb_agg(activity_row ORDER BY activity_row->>'created_at' DESC)
      FROM (
        SELECT jsonb_build_object(
          'id', activity.id,
          'kind', 'DEAL',
          'action', activity.action,
          'note', activity.note,
          'from_status', activity.from_status,
          'to_status', activity.to_status,
          'actor_id', activity.actor_id,
          'created_at', activity.created_at,
          'deal_id', activity.deal_id
        ) AS activity_row
        FROM public.crm_deal_activity activity
        JOIN public.crm_deals deal ON deal.id = activity.deal_id
        WHERE deal.client_id = v_client.id
          AND public.can_access_crm(auth.uid())
        UNION ALL
        SELECT jsonb_build_object(
          'id', update_row.id,
          'kind', 'PROJECT',
          'action', update_row.update_type,
          'note', update_row.summary,
          'actor_id', update_row.author_id,
          'created_at', update_row.created_at,
          'project_id', update_row.project_id
        ) AS activity_row
        FROM public.project_updates update_row
        JOIN public.projects project ON project.id = update_row.project_id
        WHERE project.client_id = v_client.id
          AND public.can_access_project(project.id, auth.uid())
      ) activity_rows
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_crm_client_secure(p_client jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_client public.crm_clients%ROWTYPE;
  v_name text := NULLIF(BTRIM(COALESCE(p_client->>'name', '')), '');
  v_assigned_to uuid := NULLIF(p_client->>'assigned_to', '')::uuid;
  v_status text := UPPER(BTRIM(COALESCE(NULLIF(p_client->>'status', ''), 'ACTIVE')));
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  IF v_name IS NULL OR char_length(v_name) > 200 THEN
    RAISE EXCEPTION 'Client name is required and must be 200 characters or fewer' USING ERRCODE = '22023';
  END IF;
  IF char_length(v_status) > 40 THEN
    RAISE EXCEPTION 'Client status is invalid' USING ERRCODE = '22023';
  END IF;
  IF v_assigned_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id = v_assigned_to AND profile.is_active IS DISTINCT FROM false
  ) THEN
    RAISE EXCEPTION 'Client assignee is invalid' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.crm_clients(name, email, phone, company, status, assigned_to)
  VALUES (
    v_name,
    NULLIF(BTRIM(p_client->>'email'), ''),
    NULLIF(BTRIM(p_client->>'phone'), ''),
    NULLIF(BTRIM(p_client->>'company'), ''),
    v_status,
    v_assigned_to
  )
  RETURNING * INTO v_client;

  RETURN public.crm_client_dto(v_client);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_crm_client_secure(p_client_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_client public.crm_clients%ROWTYPE;
  v_assigned_to uuid;
  v_status text;
  v_name text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_client FROM public.crm_clients WHERE id = p_client_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Client not found or access denied' USING ERRCODE = '42501';
  END IF;

  v_name := CASE WHEN p_patch ? 'name' THEN NULLIF(BTRIM(COALESCE(p_patch->>'name', '')), '') ELSE v_client.name END;
  IF v_name IS NULL OR char_length(v_name) > 200 THEN
    RAISE EXCEPTION 'Client name is required and must be 200 characters or fewer' USING ERRCODE = '22023';
  END IF;
  v_status := CASE WHEN p_patch ? 'status' THEN UPPER(BTRIM(COALESCE(p_patch->>'status', ''))) ELSE v_client.status END;
  IF v_status IS NULL OR char_length(v_status) > 40 THEN
    RAISE EXCEPTION 'Client status is invalid' USING ERRCODE = '22023';
  END IF;
  v_assigned_to := CASE WHEN p_patch ? 'assigned_to' THEN NULLIF(p_patch->>'assigned_to', '')::uuid ELSE v_client.assigned_to END;
  IF v_assigned_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id = v_assigned_to AND profile.is_active IS DISTINCT FROM false
  ) THEN
    RAISE EXCEPTION 'Client assignee is invalid' USING ERRCODE = '22023';
  END IF;

  UPDATE public.crm_clients
  SET name = v_name,
      email = CASE WHEN p_patch ? 'email' THEN NULLIF(BTRIM(p_patch->>'email'), '') ELSE email END,
      phone = CASE WHEN p_patch ? 'phone' THEN NULLIF(BTRIM(p_patch->>'phone'), '') ELSE phone END,
      company = CASE WHEN p_patch ? 'company' THEN NULLIF(BTRIM(p_patch->>'company'), '') ELSE company END,
      status = v_status,
      assigned_to = v_assigned_to
  WHERE id = p_client_id
  RETURNING * INTO v_client;

  RETURN public.crm_client_dto(v_client);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_crm_client_secure(p_client_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.crm_clients WHERE id = p_client_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Client not found or access denied' USING ERRCODE = '42501';
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_client_dto(public.crm_clients) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_crm_clients_secure(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_crm_client_secure(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_crm_client_secure(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_crm_client_secure(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_crm_client_secure(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_crm_clients_secure(text), public.get_crm_client_secure(uuid), public.create_crm_client_secure(jsonb), public.update_crm_client_secure(uuid, jsonb), public.delete_crm_client_secure(uuid) TO authenticated;

REVOKE ALL ON TABLE public.crm_clients FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.crm_clients FROM authenticated;
GRANT SELECT ON TABLE public.crm_clients TO authenticated;

-- Remove the legacy public policies from the baseline. The authoritative
-- can_access_crm policy remains the only authenticated Client table policy.
DROP POLICY IF EXISTS "Users can view clients" ON public.crm_clients;
DROP POLICY IF EXISTS "Users can insert clients" ON public.crm_clients;
DROP POLICY IF EXISTS "Users can update clients" ON public.crm_clients;
DROP POLICY IF EXISTS "Users can delete clients" ON public.crm_clients;

COMMIT;
