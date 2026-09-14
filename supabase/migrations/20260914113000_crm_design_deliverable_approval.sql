-- Require final Design deliverables before the MQ-08 task enters its
-- second approval cycle, and notify every required CRM approver.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

CREATE OR REPLACE FUNCTION public.enforce_crm_design_task_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_approval record;
    v_notification_id uuid;
    v_submitter_name text;
    v_attachment_links jsonb;
BEGIN
    IF NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'
       AND LOWER(BTRIM(COALESCE(NEW.status, ''))) = 'completed'
       AND LOWER(BTRIM(COALESCE(OLD.status, ''))) IS DISTINCT FROM 'completed'
       AND current_setting('app.crm_design_task_finalize', true) IS DISTINCT FROM 'on' THEN

        IF COALESCE(cardinality(NEW.submission_links), 0) = 0 THEN
            RAISE EXCEPTION 'Upload at least one completed Design PDF or image before requesting approval'
                USING ERRCODE = '23514';
        END IF;

        SELECT * INTO v_deal
          FROM public.crm_deals
         WHERE id = NEW.crm_deal_id
         FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'The CRM deal linked to this Design task was not found'; END IF;

        -- Every resubmission starts a fresh unanimous approval round. The
        -- original Quote-and-Proposal group is CEO, GM, MQ-04, MQ-05 and the
        -- Marketing Manager, so copying it keeps both cycles aligned.
        DELETE FROM public.crm_design_task_approval_steps WHERE task_id = NEW.id;
        INSERT INTO public.crm_design_task_approval_steps(task_id, deal_id, step_order, stage_key, approver_id)
        SELECT NEW.id, NEW.crm_deal_id, step.step_order, step.stage_key, step.approver_id
          FROM public.crm_deal_approval_steps step
         WHERE step.deal_id = NEW.crm_deal_id
         ORDER BY step.step_order;

        IF NOT EXISTS (SELECT 1 FROM public.crm_design_task_approval_steps WHERE task_id = NEW.id) THEN
            RAISE EXCEPTION 'The Design approval team is not configured for this deal';
        END IF;

        NEW.status := 'Pending Approval';
        NEW.completion_requested_by := auth.uid();
        NEW.completion_requested_at := now();
        NEW.completion_approved_by := NULL;
        NEW.completion_approved_at := NULL;
        UPDATE public.crm_deals
           SET workflow_status = 'DESIGN_PENDING_APPROVAL',
               stage = 'PITCH',
               design_task_status = 'COMPLETED'
         WHERE id = NEW.crm_deal_id;

        v_submitter_name := COALESCE(public.email_profile_name(auth.uid()), 'MQ-08');
        v_attachment_links := COALESCE(to_jsonb(NEW.submission_links), '[]'::jsonb);

        FOR v_approval IN
            SELECT DISTINCT step.approver_id
              FROM public.crm_design_task_approval_steps step
             WHERE step.task_id = NEW.id
        LOOP
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            VALUES (
                v_approval.approver_id,
                v_submitter_name || ' submitted completed Design files for approval: ' || NEW.title,
                'crm_design_task_approval_requested',
                NEW.id,
                auth.uid(),
                '/?view=approvals',
                jsonb_build_object(
                    'deal_id', NEW.crm_deal_id,
                    'task_title', NEW.title,
                    'submitted_by', v_submitter_name,
                    'attachment_links', v_attachment_links
                )
            ) RETURNING id INTO v_notification_id;

            BEGIN
                INSERT INTO public.task_email_outbox(
                    notification_id, task_id, recipient_id, recipient_email,
                    subject, message, action_url, attachment_links,
                    always_send, context_type, details
                )
                SELECT
                    v_notification_id,
                    NEW.id,
                    profile.id,
                    auth_user.email,
                    'Design approval required: ' || NEW.title,
                    v_submitter_name || ' submitted completed Design files for the CRM deal "' || v_deal.title || '". Review all files and approve or reject the task.',
                    '/?view=approvals',
                    v_attachment_links,
                    true,
                    'CRM_DESIGN_APPROVAL',
                    jsonb_build_object(
                        'deal_id', NEW.crm_deal_id,
                        'deal_title', v_deal.title,
                        'task_title', NEW.title,
                        'submitted_by', v_submitter_name
                    )
                FROM public.profiles profile
                JOIN auth.users auth_user ON auth_user.id = profile.id
                WHERE profile.id = v_approval.approver_id
                  AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Unable to queue CRM Design approval email for %: %', v_approval.approver_id, SQLERRM;
            END;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_design_task_completion_trigger ON public.tasks;
CREATE TRIGGER crm_design_task_completion_trigger
BEFORE UPDATE OF status ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.enforce_crm_design_task_completion();

REVOKE ALL ON FUNCTION public.enforce_crm_design_task_completion() FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';
COMMIT;
