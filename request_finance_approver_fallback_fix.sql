-- Prevent financial employee requests from failing when a title contains
-- spacing/alias differences or the Finance department head is not assigned.
CREATE OR REPLACE FUNCTION public.start_request_approval_workflow(p_source_table TEXT,p_source_id UUID,p_employee_id UUID,p_request_type TEXT,p_is_financial BOOLEAN DEFAULT FALSE)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_workflow_id UUID; employee public.profiles%ROWTYPE; department_manager UUID; accountant_manager UUID; general_manager UUID; fallback_manager UUID;
DECLARE approvers UUID[] := '{}'; inserted_approvers UUID[] := '{}'; stages TEXT[] := '{}'; candidate UUID; stage TEXT; position INTEGER := 0; idx INTEGER;
BEGIN
    SELECT w.id INTO v_workflow_id FROM public.request_approval_workflows w WHERE w.source_table=p_source_table AND w.source_id=p_source_id;
    IF v_workflow_id IS NOT NULL THEN RETURN v_workflow_id; END IF;
    SELECT * INTO employee FROM public.profiles WHERE id=p_employee_id;
    SELECT head_id INTO department_manager FROM public.departments WHERE id=employee.department_id;

    SELECT id INTO accountant_manager
    FROM public.profiles
    WHERE is_active IS DISTINCT FROM FALSE
      AND (upper(trim(COALESCE(job_title,''))) IN ('FINANCE MANAGER','ACCOUNTING MANAGER','ACCOUNTANT MANAGER','SENIOR ACCOUNTANT','ACCOUNTANT')
           OR upper(trim(COALESCE(role,'')))='ACCOUNTANT_MANAGER')
    ORDER BY CASE WHEN upper(trim(COALESCE(job_title,''))) IN ('FINANCE MANAGER','ACCOUNTING MANAGER','ACCOUNTANT MANAGER') THEN 0 ELSE 1 END, created_at
    LIMIT 1;

    IF accountant_manager IS NULL THEN
        SELECT head_id INTO accountant_manager
        FROM public.departments
        WHERE upper(trim(name)) LIKE '%FINANCE%' OR upper(trim(name)) LIKE '%ACCOUNTING%'
        ORDER BY CASE WHEN head_id IS NOT NULL THEN 0 ELSE 1 END
        LIMIT 1;
    END IF;

    SELECT id INTO general_manager FROM public.profiles WHERE is_active IS DISTINCT FROM FALSE AND (upper(trim(COALESCE(job_title,''))) LIKE '%GENERAL MANAGER%' OR upper(trim(COALESCE(role,'')))='GENERAL_MANAGER') ORDER BY created_at LIMIT 1;
    SELECT id INTO fallback_manager FROM public.profiles WHERE upper(trim(COALESCE(role,''))) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN') ORDER BY created_at LIMIT 1;

    approvers := ARRAY[employee.manager_id,department_manager];
    stages := ARRAY['SUPERVISOR_MANAGER','DEPARTMENT_MANAGER'];
    IF p_is_financial THEN
        accountant_manager := COALESCE(accountant_manager, fallback_manager);
        general_manager := COALESCE(general_manager, fallback_manager);
        approvers := approvers||ARRAY[accountant_manager,general_manager];
        stages := stages||ARRAY['ACCOUNTANT_MANAGER','GENERAL_MANAGER'];
    END IF;

    INSERT INTO public.request_approval_workflows(source_table,source_id,employee_id,request_type,is_financial)
    VALUES(p_source_table,p_source_id,p_employee_id,p_request_type,p_is_financial)
    RETURNING id INTO v_workflow_id;

    FOR idx IN 1..array_length(approvers,1) LOOP
        candidate:=approvers[idx]; stage:=stages[idx];
        IF candidate IS NOT NULL AND candidate<>p_employee_id AND NOT candidate=ANY(inserted_approvers) THEN
            position:=position+1;
            INSERT INTO public.request_approval_steps(workflow_id,step_order,stage_key,approver_id) VALUES(v_workflow_id,position,stage,candidate);
            inserted_approvers:=array_append(inserted_approvers,candidate);
        END IF;
    END LOOP;

    IF position=0 AND fallback_manager IS NOT NULL THEN
        position:=1;
        INSERT INTO public.request_approval_steps(workflow_id,step_order,stage_key,approver_id) VALUES(v_workflow_id,1,'ADMIN_FALLBACK',fallback_manager);
    END IF;
    IF position=0 THEN RAISE EXCEPTION 'No approver is configured for this employee request'; END IF;
    SELECT approver_id INTO candidate FROM public.request_approval_steps WHERE workflow_id=v_workflow_id AND step_order=1;
    PERFORM public.queue_request_notification(candidate,'Approval required: '||p_request_type,'request_approval_required',v_workflow_id);
    PERFORM public.queue_request_notification(p_employee_id,'Your '||p_request_type||' request was submitted and is awaiting approval.','request_status_changed',v_workflow_id);
    RETURN v_workflow_id;
END;
$$;

REVOKE ALL ON FUNCTION public.start_request_approval_workflow(TEXT,UUID,UUID,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_request_approval_workflow(TEXT,UUID,UUID,TEXT,BOOLEAN) TO authenticated;
NOTIFY pgrst, 'reload schema';
