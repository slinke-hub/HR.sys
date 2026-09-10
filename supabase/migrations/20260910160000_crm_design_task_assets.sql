-- Permit the assignee of a linked CRM Design task to read its source quote
-- and proposal assets without granting wider CRM attachment access.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

ALTER TABLE public.crm_deal_attachments ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.crm_deal_attachments TO authenticated;

DROP POLICY IF EXISTS crm_authorized_attachments_select ON public.crm_deal_attachments;
CREATE POLICY crm_authorized_attachments_select ON public.crm_deal_attachments
FOR SELECT TO authenticated
USING (
    public.can_access_crm(auth.uid())
    OR EXISTS (
        SELECT 1
          FROM public.tasks task
         WHERE task.crm_deal_id = crm_deal_attachments.deal_id
           AND task.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'
           AND auth.uid() IN (task.assignee_id, task.created_by)
    )
);

NOTIFY pgrst, 'reload schema';
COMMIT;
