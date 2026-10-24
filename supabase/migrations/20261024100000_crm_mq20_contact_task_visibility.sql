-- Allow MQ-20 to see only their own server-generated Contact discussion task.
-- All other rows remain subject to the existing Ines-only restriction.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

CREATE OR REPLACE FUNCTION public.can_view_own_crm_contact_task(
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
$$;

REVOKE ALL ON FUNCTION public.can_view_own_crm_contact_task(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_own_crm_contact_task(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS mq20_only_ines_tasks_select ON public.tasks;
CREATE POLICY mq20_only_ines_tasks_select ON public.tasks AS RESTRICTIVE
FOR SELECT TO authenticated
USING (
  NOT public.is_mq20_profile(auth.uid())
  OR public.is_ines_modani_task(id)
  OR public.can_view_own_crm_contact_task(id, auth.uid())
);

COMMIT;
