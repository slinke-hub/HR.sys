BEGIN;

ALTER TABLE public.requests
    ADD COLUMN IF NOT EXISTS start_date DATE,
    ADD COLUMN IF NOT EXISTS end_date DATE;

CREATE OR REPLACE FUNCTION public.admin_update_employee_request(
    p_source_table TEXT,
    p_source_id UUID,
    p_patch JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    request_row public.requests%ROWTYPE;
    leave_row public.leave_requests%ROWTYPE;
    request_type_value TEXT;
    leave_type_value TEXT;
    start_date_value DATE;
    end_date_value DATE;
    days_value INTEGER;
BEGIN
    IF NOT public.is_employee_request_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only administrators can edit employee requests' USING ERRCODE = '42501';
    END IF;

    IF p_source_table NOT IN ('requests', 'leave_requests', 'document_requests', 'expenses') THEN
        RAISE EXCEPTION 'Unsupported employee request type';
    END IF;

    IF p_source_table = 'requests' THEN
        SELECT * INTO request_row FROM public.requests WHERE id = p_source_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Employee request not found'; END IF;

        request_type_value := CASE WHEN p_patch ? 'request_type' THEN NULLIF(BTRIM(p_patch->>'request_type'), '') ELSE request_row.request_type END;
        leave_type_value := CASE WHEN p_patch ? 'leave_type' THEN NULLIF(BTRIM(p_patch->>'leave_type'), '') ELSE request_row.leave_type END;
        start_date_value := CASE WHEN p_patch ? 'start_date' THEN NULLIF(p_patch->>'start_date', '')::DATE ELSE request_row.start_date END;
        end_date_value := CASE WHEN p_patch ? 'end_date' THEN NULLIF(p_patch->>'end_date', '')::DATE ELSE request_row.end_date END;
        days_value := CASE WHEN p_patch ? 'number_of_days' THEN NULLIF(p_patch->>'number_of_days', '')::INTEGER ELSE request_row.number_of_days END;

        IF LOWER(COALESCE(request_type_value, '')) = 'leave request' THEN
            IF start_date_value IS NULL OR end_date_value IS NULL OR end_date_value < start_date_value THEN
                RAISE EXCEPTION 'Leave requests require a valid start and end date';
            END IF;
            days_value := (end_date_value - start_date_value) + 1;
        ELSE
            leave_type_value := NULL;
            start_date_value := NULL;
            end_date_value := NULL;
            days_value := NULL;
        END IF;

        UPDATE public.requests
        SET request_type = request_type_value,
            leave_type = leave_type_value,
            start_date = start_date_value,
            end_date = end_date_value,
            number_of_days = days_value,
            loan_amount = CASE WHEN p_patch ? 'loan_amount' THEN NULLIF(p_patch->>'loan_amount', '')::NUMERIC ELSE request_row.loan_amount END
        WHERE id = p_source_id;
    ELSIF p_source_table = 'leave_requests' THEN
        SELECT * INTO leave_row FROM public.leave_requests WHERE id = p_source_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Employee request not found'; END IF;

        start_date_value := CASE WHEN p_patch ? 'start_date' THEN NULLIF(p_patch->>'start_date', '')::DATE ELSE leave_row.start_date END;
        end_date_value := CASE WHEN p_patch ? 'end_date' THEN NULLIF(p_patch->>'end_date', '')::DATE ELSE leave_row.end_date END;
        IF start_date_value IS NULL OR end_date_value IS NULL OR end_date_value < start_date_value THEN
            RAISE EXCEPTION 'Leave requests require a valid start and end date';
        END IF;

        UPDATE public.leave_requests
        SET leave_type = CASE WHEN p_patch ? 'leave_type' THEN NULLIF(BTRIM(p_patch->>'leave_type'), '') ELSE leave_row.leave_type END,
            start_date = start_date_value,
            end_date = end_date_value,
            reason = CASE WHEN p_patch ? 'reason' THEN NULLIF(p_patch->>'reason', '') ELSE leave_row.reason END,
            short_leave_reason = CASE WHEN p_patch ? 'short_leave_reason' THEN NULLIF(p_patch->>'short_leave_reason', '') ELSE leave_row.short_leave_reason END,
            short_leave_duration_minutes = CASE WHEN p_patch ? 'short_leave_duration_minutes' THEN NULLIF(p_patch->>'short_leave_duration_minutes', '')::INTEGER ELSE leave_row.short_leave_duration_minutes END
        WHERE id = p_source_id;
    ELSIF p_source_table = 'document_requests' THEN
        EXECUTE 'UPDATE public.document_requests SET doc_type = COALESCE(NULLIF(BTRIM($1->>''doc_type''), ''''), doc_type), purpose = COALESCE(NULLIF($1->>''purpose'', ''''), purpose) WHERE id = $2'
        USING p_patch, p_source_id;
    ELSE
        EXECUTE 'UPDATE public.expenses SET amount = COALESCE(NULLIF($1->>''amount'', '''')::NUMERIC, amount), description = COALESCE(NULLIF($1->>''description'', ''''), description) WHERE id = $2'
        USING p_patch, p_source_id;
    END IF;

    RETURN jsonb_build_object('updated', TRUE, 'source_table', p_source_table, 'source_id', p_source_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_employee_request(TEXT, UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_employee_request(TEXT, UUID, JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
