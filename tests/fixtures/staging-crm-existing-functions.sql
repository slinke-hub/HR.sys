-- Exact Staging function definitions and grants from the 2026-11-09 catalog; synthetic schema/data only.
CREATE OR REPLACE FUNCTION public.crm_is_own_generated_contact_task(p_task_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_task_id IS NOT NULL
    AND p_user_id IS NOT NULL
    AND p_user_id = auth.uid()
    AND public.is_mq20_profile(p_user_id)
    AND EXISTS (
      SELECT 1
      FROM public.crm_generated_tasks generated
      JOIN public.tasks task ON task.id = generated.task_id
      WHERE generated.task_id = p_task_id
        AND generated.kind = 'CONTACT_DISCUSSION'
        AND generated.deal_id = task.crm_deal_id
        AND task.crm_workflow_kind = 'CONTACT_DISCUSSION'
        AND task.created_by = p_user_id
        AND task.assignee_id = p_user_id
        AND p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
    );
$function$;
REVOKE ALL ON FUNCTION public.crm_is_own_generated_contact_task(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_is_own_generated_contact_task(uuid,uuid) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION public.can_access_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.tasks task
    WHERE task.id = p_task_id
      AND p_user_id IS NOT NULL
      AND (auth.uid() IS NULL OR p_user_id = auth.uid())
      AND (
        auth.uid() IS NULL
        OR NOT public.is_mq20_profile(auth.uid())
        OR public.is_ines_modani_task(task.id)
        OR public.crm_is_own_generated_contact_task(task.id, auth.uid())
      )
      AND (
        task.created_by = p_user_id
        OR task.assignee_id = p_user_id
        OR task.supervisor_id = p_user_id
        OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
        OR p_user_id = ANY(COALESCE(task.visible_to, '{}'::uuid[]))
        OR public.can_assign_tasks_company_wide(p_user_id)
        OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
        OR public.can_view_task_via_employee_grant(p_task_id, p_user_id)
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list(task.task_list_id, p_user_id))
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list_via_employee_grant(task.task_list_id, p_user_id))
      )
  );
$function$;
REVOKE ALL ON FUNCTION public.can_access_task(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_access_task(uuid,uuid) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION public.can_view_own_crm_contact_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_user_id IS NOT NULL
     AND p_user_id = auth.uid()
     AND public.is_mq20_profile(p_user_id)
     AND public.can_access_task(p_task_id, p_user_id)
     AND EXISTS (
       SELECT 1
       FROM public.tasks task
       JOIN public.crm_generated_tasks generated
         ON generated.task_id = task.id
        AND generated.deal_id = task.crm_deal_id
        AND generated.kind = 'CONTACT_DISCUSSION'
       WHERE task.id = p_task_id
         AND task.crm_workflow_kind = 'CONTACT_DISCUSSION'
         AND task.created_by = p_user_id
         AND task.assignee_id = p_user_id
         AND p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
     );
$function$;
REVOKE ALL ON FUNCTION public.can_view_own_crm_contact_task(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_own_crm_contact_task(uuid,uuid) TO authenticated, service_role;
CREATE OR REPLACE FUNCTION public.decide_crm_design_task_approval(p_step_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_step public.crm_design_task_approval_steps%ROWTYPE;
    v_task public.tasks%ROWTYPE;
    v_deal public.crm_deals%ROWTYPE;
    v_remaining integer;
    v_notification_id uuid;
BEGIN
    p_decision := UPPER(BTRIM(COALESCE(p_decision, '')));
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'Invalid approval decision'; END IF;
    IF p_decision = 'REJECTED' AND NULLIF(BTRIM(COALESCE(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'A rejection reason is required'; END IF;
    SELECT * INTO v_step FROM public.crm_design_task_approval_steps WHERE id = p_step_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Design approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;
    UPDATE public.crm_design_task_approval_steps SET status = p_decision, decision_note = NULLIF(BTRIM(p_note), ''), decided_at = now()
    WHERE id = p_step_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval has already been decided'; END IF;
    SELECT * INTO v_task FROM public.tasks WHERE id = v_step.task_id;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_step.deal_id;
    IF p_decision = 'REJECTED' THEN
        UPDATE public.tasks SET status = 'in_progress', completion_requested_by = NULL, completion_requested_at = NULL WHERE id = v_task.id;
        UPDATE public.crm_deals SET workflow_status = 'DESIGN_REJECTED' WHERE id = v_deal.id;
        SELECT id INTO v_notification_id FROM public.notifications
        WHERE task_id = v_task.id AND user_id = v_task.assignee_id
        ORDER BY created_at DESC LIMIT 1;
        IF v_notification_id IS NULL THEN
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            VALUES (v_task.assignee_id, 'CRM Design task rejected: ' || v_task.title || '. Reason: ' || BTRIM(p_note), 'crm_design_task_rejected', v_task.id, auth.uid(), '/?view=tasks', jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note)))
            RETURNING id INTO v_notification_id;
        ELSE
            UPDATE public.notifications
               SET message = 'CRM Design task rejected: ' || v_task.title || '. Reason: ' || BTRIM(p_note),
                   event_type = 'crm_design_task_rejected',
                   metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note))
             WHERE id = v_notification_id;
        END IF;
        INSERT INTO public.task_email_outbox(notification_id, task_id, recipient_id, recipient_email, subject, message, action_url, always_send)
        SELECT v_notification_id, v_task.id, profile.id, auth_user.email, 'CRM Design task needs changes: ' || v_task.title,
               'Reason: ' || BTRIM(p_note), '/?view=tasks', true
        FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE profile.id = v_task.assignee_id AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
    ELSE
        SELECT count(*) INTO v_remaining FROM public.crm_design_task_approval_steps WHERE task_id = v_task.id AND status <> 'APPROVED';
        IF v_remaining = 0 THEN
            PERFORM set_config('app.crm_design_task_finalize', 'on', true);
            UPDATE public.tasks SET status = 'completed', completion_approved_by = auth.uid(), completion_approved_at = now() WHERE id = v_task.id;
            UPDATE public.crm_deals SET stage = 'NEGOTIATION', workflow_status = 'APPROVED' WHERE id = v_deal.id;
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            SELECT recipient, 'CRM Design approved and deal moved to Discussion: ' || v_deal.title,
                   'crm_design_task_approved', v_task.id, auth.uid(), '/?view=crm', jsonb_build_object('deal_id', v_deal.id)
            FROM unnest(array_remove(ARRAY[v_task.assignee_id, COALESCE(v_deal.created_by, v_deal.assigned_to)], NULL)) recipient;
        END IF;
    END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.decide_crm_design_task_approval(uuid,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.decide_crm_design_task_approval(uuid,text,text) TO service_role;
-- STAGING_QUEUE_TASK_NOTIFICATION_DEFINITION
REVOKE ALL ON FUNCTION public.queue_task_notification(uuid,uuid,text,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.queue_task_notification(uuid,uuid,text,text) TO PUBLIC, anon, authenticated, service_role;
