BEGIN;

-- Administrators retain their existing delete authority. Request owners may
-- withdraw only their own request while its approval workflow is still pending.
CREATE OR REPLACE FUNCTION public.admin_delete_employee_request(
    p_source_table TEXT,
    p_source_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    source_row JSONB;
    source_owner UUID;
    source_status TEXT;
    workflow_status TEXT;
    actor_is_admin BOOLEAN := FALSE;
    owner_can_withdraw BOOLEAN := FALSE;
    deleted_count INTEGER := 0;
BEGIN
    IF p_source_table NOT IN ('requests', 'leave_requests', 'document_requests', 'expenses') THEN
        RAISE EXCEPTION 'Unsupported employee request type';
    END IF;

    EXECUTE format(
        'SELECT to_jsonb(request_row) FROM public.%I request_row WHERE id = $1',
        p_source_table
    ) INTO source_row USING p_source_id;

    IF source_row IS NULL THEN
        RAISE EXCEPTION 'Employee request not found';
    END IF;

    source_owner := NULLIF(source_row->>'employee_id', '')::UUID;
    source_status := UPPER(COALESCE(source_row->>'status', 'PENDING'));

    SELECT workflow.status
      INTO workflow_status
      FROM public.request_approval_workflows workflow
     WHERE workflow.source_table = p_source_table
       AND workflow.source_id = p_source_id
     ORDER BY workflow.created_at DESC
     LIMIT 1;

    actor_is_admin := public.is_employee_request_admin(auth.uid());
    owner_can_withdraw := source_owner = auth.uid()
        AND COALESCE(NULLIF(source_row->>'is_archived', '')::BOOLEAN, FALSE) IS FALSE
        AND source_status LIKE 'PENDING%'
        AND COALESCE(UPPER(workflow_status), 'PENDING') = 'PENDING';

    IF NOT actor_is_admin AND NOT owner_can_withdraw THEN
        RAISE EXCEPTION 'Only administrators, or the request owner before final approval, can delete this request'
            USING ERRCODE = '42501';
    END IF;

    DELETE FROM public.request_approval_workflows
    WHERE source_table = p_source_table AND source_id = p_source_id;

    DELETE FROM public.notifications
    WHERE metadata->>'source_table' = p_source_table
      AND metadata->>'source_id' = p_source_id::TEXT;

    EXECUTE format('DELETE FROM public.%I WHERE id = $1', p_source_table) USING p_source_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    IF deleted_count = 0 THEN RAISE EXCEPTION 'Employee request not found'; END IF;

    RETURN jsonb_build_object(
        'deleted', TRUE,
        'withdrawn_by_owner', owner_can_withdraw AND NOT actor_is_admin,
        'source_table', p_source_table,
        'source_id', p_source_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_employee_request(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_employee_request(TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
