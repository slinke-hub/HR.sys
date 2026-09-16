BEGIN;

DROP FUNCTION IF EXISTS public.get_my_request_statuses();

CREATE OR REPLACE FUNCTION public.get_my_request_statuses()
RETURNS TABLE(
  source_table TEXT,
  request_id UUID,
  request_type TEXT,
  request_details TEXT,
  request_status TEXT,
  current_stage TEXT,
  current_approver_id UUID,
  current_approver_name TEXT,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ,
  submitter_name TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  WITH request_source AS (
    SELECT 'requests'::TEXT source_table,request.id request_id,
      COALESCE(request.request_type,'Employee Request')::TEXT request_type,
      CASE
        WHEN lower(COALESCE(request.request_type,'')) LIKE 'loan%' THEN 'Loan amount: '||COALESCE(request.loan_amount::TEXT,'0')||' SAR'
        WHEN request.request_type='Leave Request' THEN COALESCE(request.leave_type,'Leave')||' — '||COALESCE(request.number_of_days::TEXT,'0')||' day(s)'
        ELSE COALESCE(request.leave_type,request.request_type,'Employee Request')
      END::TEXT request_details,
      COALESCE(request.status,'PENDING')::TEXT source_status,request.created_at,
      request.employee_id
    FROM public.requests request WHERE request.employee_id=auth.uid()
    UNION ALL
    SELECT 'leave_requests',request.id,'Leave',
      CASE 
        WHEN request.leave_type = 'Short Leave' THEN 
          COALESCE(request.leave_type,'Leave')||' — '||
          CASE WHEN request.short_leave_duration_minutes = 1440 THEN '1 Day' ELSE COALESCE(request.short_leave_duration_minutes::TEXT, '0')||' minutes' END
        ELSE
          COALESCE(request.leave_type,'Leave')||' — '||COALESCE(EXTRACT(DAY FROM (request.end_date::timestamp - request.start_date::timestamp)) + 1, 0)::TEXT||' day(s)'
      END::TEXT,
      COALESCE(request.status,'PENDING'),request.created_at,
      request.employee_id
    FROM public.leave_requests request WHERE request.employee_id=auth.uid()
    UNION ALL
    SELECT 'document_requests',request.id,'Document',
      COALESCE(request.doc_type,'Document')||' — '||COALESCE(request.purpose,'No purpose provided'),
      COALESCE(request.status,'PENDING'),request.created_at,
      request.employee_id
    FROM public.document_requests request WHERE request.employee_id=auth.uid()
    UNION ALL
    SELECT 'expenses',request.id,'Expense',
      COALESCE(request.amount::TEXT,'0')||' SAR — '||COALESCE(request.description,'No description'),
      COALESCE(request.status,'PENDING'),request.created_at,
      request.employee_id
    FROM public.expenses request WHERE request.employee_id=auth.uid()
  )
  SELECT source.source_table,source.request_id,source.request_type,source.request_details,
    COALESCE(workflow.status,upper(source.source_status))::TEXT request_status,
    step.stage_key::TEXT current_stage,step.approver_id,
    COALESCE(approver.full_name,'Management')::TEXT current_approver_name,
    COALESCE(step.decision_note,'')::TEXT rejection_reason,
    source.created_at,
    COALESCE(submitter.full_name, 'Unknown')::TEXT submitter_name
  FROM request_source source
  LEFT JOIN public.profiles submitter ON submitter.id=source.employee_id
  LEFT JOIN public.request_approval_workflows workflow
    ON workflow.source_table=source.source_table AND workflow.source_id=source.request_id
  LEFT JOIN public.request_approval_steps step
    ON step.workflow_id=workflow.id AND step.step_order=workflow.current_step
  LEFT JOIN public.profiles approver ON approver.id=step.approver_id
  ORDER BY source.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.get_my_request_statuses() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_request_statuses() TO authenticated;

COMMIT;
