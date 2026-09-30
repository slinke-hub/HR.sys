-- Reviewed production migration generated from the verified service artifact.
-- Source artifact: deal_backend_services.sql
-- No environment reference, test identity, synthetic fixture, or cleanup harness is included.
-- HR.sys reviewed production Deal backend façade.
-- Apply only to the linked security-project after a project-ref check.
-- No data is seeded by this file.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_crm_deal_secure(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deal public.crm_deals%ROWTYPE;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT to_jsonb(v_deal)
         || jsonb_build_object(
              'amount', CASE WHEN public.can_view_business_financials(auth.uid())
                             THEN to_jsonb(v_deal.amount) ELSE 'null'::jsonb END,
              'crm_clients', CASE WHEN client.id IS NULL THEN NULL ELSE to_jsonb(client) END
            )
    INTO v_result
    FROM public.crm_clients client
   WHERE client.id = v_deal.client_id;
  IF v_result IS NULL THEN
    v_result := to_jsonb(v_deal)
      || jsonb_build_object('amount', CASE WHEN public.can_view_business_financials(auth.uid())
                                           THEN to_jsonb(v_deal.amount) ELSE 'null'::jsonb END,
                            'crm_clients', NULL);
  END IF;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_crm_deal_secure(p_deal jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
  v_client_id uuid;
  v_assigned_to uuid;
  v_title text := NULLIF(BTRIM(COALESCE(p_deal->>'title', '')), '');
  v_first_contact date := NULLIF(BTRIM(COALESCE(p_deal->>'first_contact_date', '')), '')::date;
  v_contact_method text := NULLIF(BTRIM(COALESCE(p_deal->>'contact_method', '')), '');
  v_amount numeric := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  IF v_title IS NULL THEN RAISE EXCEPTION 'Deal title is required' USING ERRCODE = '22023'; END IF;
  IF v_first_contact IS NULL THEN RAISE EXCEPTION 'First contact date is required' USING ERRCODE = '23514'; END IF;
  IF v_contact_method IS NULL THEN RAISE EXCEPTION 'Contact method is required' USING ERRCODE = '23514'; END IF;
  IF NULLIF(BTRIM(COALESCE(p_deal->>'client_id', '')), '') IS NULL THEN
    RAISE EXCEPTION 'Client is required' USING ERRCODE = '23514';
  END IF;
  v_client_id := (p_deal->>'client_id')::uuid;
  IF NOT EXISTS (SELECT 1 FROM public.crm_clients WHERE id = v_client_id) THEN
    RAISE EXCEPTION 'CRM client not found' USING ERRCODE = 'P0002';
  END IF;
  v_assigned_to := NULLIF(BTRIM(COALESCE(p_deal->>'assigned_to', '')), '')::uuid;
  IF v_assigned_to IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_assigned_to AND is_active IS DISTINCT FROM false
  ) THEN
    RAISE EXCEPTION 'Deal assignee must be an active employee' USING ERRCODE = '23514';
  END IF;
  IF public.can_view_business_financials(auth.uid())
     AND NULLIF(BTRIM(COALESCE(p_deal->>'amount', '')), '') IS NOT NULL THEN
    v_amount := (p_deal->>'amount')::numeric;
  END IF;
  INSERT INTO public.crm_deals(
    client_id, title, amount, stage, closing_date, assigned_to, event_type,
    first_contact_date, contact_method, lead_source, technical_description, created_by
  ) VALUES (
    v_client_id, v_title, v_amount, 'LEAD', NULLIF(p_deal->>'closing_date', '')::date,
    v_assigned_to, NULLIF(p_deal->>'event_type', ''), v_first_contact, v_contact_method,
    NULLIF(p_deal->>'lead_source', ''), NULLIF(p_deal->>'technical_description', ''), auth.uid()
  ) RETURNING id INTO v_id;
  INSERT INTO public.crm_deal_activity(deal_id, action, to_status, actor_id)
  VALUES (v_id, 'DEAL_CREATED', 'LEAD', auth.uid());
  RETURN public.get_crm_deal_secure(v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_crm_deal_secure(p_deal_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deal public.crm_deals%ROWTYPE;
  v_client_id uuid;
  v_assigned_to uuid;
  v_amount numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
  IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN
    RAISE EXCEPTION 'Lost deals are read-only until moved to another stage' USING ERRCODE = '42501';
  END IF;
  IF p_patch ? 'client_id' THEN
    v_client_id := NULLIF(BTRIM(COALESCE(p_patch->>'client_id', '')), '')::uuid;
    IF v_client_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.crm_clients WHERE id = v_client_id) THEN
      RAISE EXCEPTION 'CRM client not found' USING ERRCODE = 'P0002';
    END IF;
  ELSE v_client_id := v_deal.client_id;
  END IF;
  IF p_patch ? 'assigned_to' THEN
    v_assigned_to := NULLIF(BTRIM(COALESCE(p_patch->>'assigned_to', '')), '')::uuid;
    IF v_assigned_to IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE id = v_assigned_to AND is_active IS DISTINCT FROM false
    ) THEN
      RAISE EXCEPTION 'Deal assignee must be an active employee' USING ERRCODE = '23514';
    END IF;
  ELSE v_assigned_to := v_deal.assigned_to;
  END IF;
  IF public.can_view_business_financials(auth.uid()) AND p_patch ? 'amount' THEN
    v_amount := NULLIF(BTRIM(COALESCE(p_patch->>'amount', '')), '')::numeric;
  ELSE v_amount := v_deal.amount;
  END IF;
  UPDATE public.crm_deals SET
    title = COALESCE(NULLIF(BTRIM(COALESCE(p_patch->>'title', '')), ''), title),
    client_id = v_client_id,
    amount = COALESCE(v_amount, 0),
    closing_date = CASE WHEN p_patch ? 'closing_date' THEN NULLIF(p_patch->>'closing_date', '')::date ELSE closing_date END,
    assigned_to = v_assigned_to,
    event_type = CASE WHEN p_patch ? 'event_type' THEN NULLIF(p_patch->>'event_type', '') ELSE event_type END,
    first_contact_date = CASE WHEN p_patch ? 'first_contact_date' THEN NULLIF(p_patch->>'first_contact_date', '')::date ELSE first_contact_date END,
    contact_method = CASE WHEN p_patch ? 'contact_method' THEN NULLIF(BTRIM(COALESCE(p_patch->>'contact_method', '')), '') ELSE contact_method END,
    lead_source = CASE WHEN p_patch ? 'lead_source' THEN NULLIF(p_patch->>'lead_source', '') ELSE lead_source END,
    technical_description = CASE WHEN p_patch ? 'technical_description' THEN NULLIF(p_patch->>'technical_description', '') ELSE technical_description END
  WHERE id = p_deal_id;
  INSERT INTO public.crm_deal_activity(deal_id, action, actor_id, note)
  VALUES (p_deal_id, CASE WHEN v_deal.assigned_to IS DISTINCT FROM v_assigned_to THEN 'DEAL_REASSIGNED' ELSE 'DEAL_UPDATED' END,
          auth.uid(), NULLIF((p_patch - 'amount')::text, '{}'));
  RETURN public.get_crm_deal_secure(p_deal_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_crm_deal_secure(p_deal_id uuid, p_assignee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_assignee_id IS NULL THEN RAISE EXCEPTION 'Deal assignee is required' USING ERRCODE = '22023'; END IF;
  RETURN public.update_crm_deal_secure(p_deal_id, jsonb_build_object('assigned_to', p_assignee_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.list_crm_deal_activity_secure(p_deal_id uuid)
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT to_jsonb(activity) || jsonb_build_object('profiles', CASE WHEN profile.id IS NULL THEN NULL ELSE to_jsonb(profile) END)
    FROM public.crm_deal_activity activity
    LEFT JOIN public.profiles profile ON profile.id = activity.actor_id
   WHERE activity.deal_id = p_deal_id
     AND auth.uid() IS NOT NULL AND public.can_access_crm(auth.uid())
   ORDER BY activity.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.list_crm_deal_attachments_secure(p_deal_id uuid)
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT to_jsonb(attachment)
    FROM public.crm_deal_attachments attachment
   WHERE attachment.deal_id = p_deal_id
     AND attachment.is_archived = false
     AND auth.uid() IS NOT NULL AND public.can_access_crm(auth.uid())
   ORDER BY attachment.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_crm_deal_attachment_secure(p_attachment_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT to_jsonb(attachment)
    FROM public.crm_deal_attachments attachment
   WHERE attachment.id = p_attachment_id
     AND attachment.is_archived = false
     AND auth.uid() IS NOT NULL AND public.can_access_crm(auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.register_crm_deal_attachment_secure(
  p_deal_id uuid, p_category text, p_file_name text, p_file_url text,
  p_description text DEFAULT NULL, p_file_type text DEFAULT NULL,
  p_file_size bigint DEFAULT NULL, p_visible_to_project_assignee boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_row public.crm_deal_attachments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id = p_deal_id) THEN
    RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_file_name, '')), '') IS NULL OR NULLIF(BTRIM(COALESCE(p_file_url, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Attachment name and storage reference are required' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.crm_deal_attachments(
    deal_id, category, file_name, file_url, description, uploaded_by, file_type, file_size, visible_to_project_assignee
  ) VALUES (
    p_deal_id, UPPER(BTRIM(COALESCE(p_category, 'OTHER'))), p_file_name, p_file_url,
    NULLIF(p_description, ''), auth.uid(), NULLIF(p_file_type, ''), p_file_size, COALESCE(p_visible_to_project_assignee, false)
  ) RETURNING * INTO v_row;
  INSERT INTO public.crm_deal_activity(deal_id, action, actor_id, note)
  VALUES (p_deal_id, 'ATTACHMENT_ADDED', auth.uid(), v_row.file_name);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_crm_deal_attachment_secure(p_attachment_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_row public.crm_deal_attachments%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_row FROM public.crm_deal_attachments WHERE id = p_attachment_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_row.uploaded_by IS DISTINCT FROM auth.uid() AND NOT public.can_delete_crm_deal(auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized to remove this Deal attachment' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.crm_deal_attachments WHERE id = p_attachment_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_crm_deal_activity_secure(
  p_deal_id uuid, p_action text, p_from_status text DEFAULT NULL,
  p_to_status text DEFAULT NULL, p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
    RAISE EXCEPTION 'CRM access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id = p_deal_id) THEN
    RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002';
  END IF;
  INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
  VALUES (p_deal_id, NULLIF(BTRIM(COALESCE(p_action, '')), ''), p_from_status, p_to_status, p_note, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- The façade is the only authenticated write path for CRM deals and their
-- attachment/activity records. SELECT remains available to the existing web
-- workflow and is still protected by table RLS; anonymous clients get none.
REVOKE ALL ON TABLE public.crm_deals, public.crm_deal_activity, public.crm_deal_attachments FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.crm_deals, public.crm_deal_activity, public.crm_deal_attachments FROM authenticated;
GRANT SELECT ON TABLE public.crm_deals, public.crm_deal_activity, public.crm_deal_attachments TO authenticated;

REVOKE ALL ON FUNCTION public.get_crm_deal_secure(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_crm_deal_secure(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_crm_deal_secure(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_crm_deal_secure(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_crm_deal_activity_secure(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_crm_deal_attachments_secure(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_crm_deal_attachment_secure(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.register_crm_deal_attachment_secure(uuid, text, text, text, text, text, bigint, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.log_crm_deal_activity_secure(uuid, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_crm_deal_attachment_secure(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_crm_deal_secure(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_crm_deal_secure(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_crm_deal_secure(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_crm_deal_secure(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_crm_deal_activity_secure(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_crm_deal_attachments_secure(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_crm_deal_attachment_secure(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_crm_deal_attachment_secure(uuid, text, text, text, text, text, bigint, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_crm_deal_activity_secure(uuid, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_deal_attachment_secure(uuid) TO authenticated;

-- Existing workflow RPCs are protected from anonymous invocation as well.
REVOKE EXECUTE ON FUNCTION public.create_crm_design_task_for_deal(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.start_crm_presentation_approval(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.decide_crm_design_task_approval(uuid, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.archive_crm_deal_attachments(uuid, text[], uuid[]) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_project_from_won_deal_v2(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_crm_design_task_for_deal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_crm_presentation_approval(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decide_crm_design_task_approval(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_crm_deal_attachments(uuid, text[], uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_project_from_won_deal_v2(uuid, jsonb) TO authenticated;

-- Storage sign requests evaluate policies as the storage role.  Keep the
-- relationship check in a SECURITY DEFINER helper so a CRM user does not
-- need direct SELECT grants on projects just to download a private Deal file.
CREATE OR REPLACE FUNCTION public.can_read_crm_deal_file(p_object_name text, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF public.can_access_crm(p_user_id) THEN RETURN true; END IF;
  RETURN EXISTS (
    SELECT 1
      FROM public.crm_deal_attachments attachment
      JOIN public.projects project ON project.deal_id = attachment.deal_id
     WHERE attachment.file_url = 'storage://crm-deal-files/' || p_object_name
       AND attachment.is_archived = false
       AND attachment.visible_to_project_assignee = true
       AND p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::uuid[]))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.can_read_crm_deal_file(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_crm_deal_file(text, uuid) TO authenticated;
DROP POLICY IF EXISTS sensitive_crm_deal_files_read ON storage.objects;
CREATE POLICY sensitive_crm_deal_files_read ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'crm-deal-files' AND public.can_read_crm_deal_file(name, auth.uid()));

-- Storage evaluates every SELECT policy on storage.objects.  The existing
-- task policy previously joined public.projects as the invoker, which caused
-- a harmless CRM signed-URL request to fail for roles without direct project
-- table grants.  Keep the same rule in a definer helper.
CREATE OR REPLACE FUNCTION public.can_read_task_attachment_file(p_object_name text, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
      FROM public.task_attachments attachment
      LEFT JOIN public.tasks task ON task.id = attachment.task_id
      LEFT JOIN public.projects project ON project.id = task.project_id
     WHERE attachment.file_url = 'storage://task-attachments/' || p_object_name
       AND (public.can_access_task(task.id, p_user_id)
            OR (project.id IS NOT NULL AND p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::uuid[]))))
  );
END;
$$;
REVOKE ALL ON FUNCTION public.can_read_task_attachment_file(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_task_attachment_file(text, uuid) TO authenticated;
DROP POLICY IF EXISTS sensitive_task_attachments_read ON storage.objects;
CREATE POLICY sensitive_task_attachments_read ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'task-attachments' AND public.can_read_task_attachment_file(name, auth.uid()));

NOTIFY pgrst, 'reload schema';

COMMIT;
