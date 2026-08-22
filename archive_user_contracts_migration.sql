-- Archive an employee's contracts while permanently removing the employee and
-- all records that reference the employee. Run once in the Supabase SQL editor.
ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_by UUID,
    ADD COLUMN IF NOT EXISTS former_employee_name TEXT,
    ADD COLUMN IF NOT EXISTS former_employee_email TEXT,
    ADD COLUMN IF NOT EXISTS former_employee_number TEXT;

ALTER TABLE public.contracts ALTER COLUMN employee_id DROP NOT NULL;

DO $$
DECLARE fk RECORD;
BEGIN
    FOR fk IN
        SELECT con.conname FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = rel.relnamespace
        JOIN unnest(con.conkey) AS key(attnum) ON TRUE
        JOIN pg_attribute att ON att.attrelid = rel.oid AND att.attnum = key.attnum
        WHERE con.contype = 'f' AND ns.nspname = 'public'
          AND rel.relname = 'contracts' AND att.attname = 'employee_id'
    LOOP
        EXECUTE format('ALTER TABLE public.contracts DROP CONSTRAINT %I', fk.conname);
    END LOOP;
END $$;

ALTER TABLE public.contracts ADD CONSTRAINT contracts_employee_id_fkey
    FOREIGN KEY (employee_id) REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS contracts_archived_idx ON public.contracts (is_archived, archived_at DESC);

CREATE OR REPLACE FUNCTION public.archive_and_delete_employee(target_user_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
    target_profile public.profiles%ROWTYPE;
    target_email TEXT;
    archived_count INTEGER := 0;
    ref RECORD;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND UPPER(COALESCE(role, '')) = 'ADMIN') THEN
        RAISE EXCEPTION 'Only an administrator can delete an employee';
    END IF;
    IF target_user_id = auth.uid() THEN
        RAISE EXCEPTION 'Administrators cannot delete their own signed-in account';
    END IF;

    SELECT * INTO target_profile FROM public.profiles WHERE id = target_user_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Employee not found'; END IF;
    SELECT email INTO target_email FROM auth.users WHERE id = target_user_id;

    UPDATE public.contracts SET
        is_archived = TRUE, archived_at = NOW(), archived_by = auth.uid(),
        former_employee_name = COALESCE(former_employee_name, target_profile.full_name),
        former_employee_email = COALESCE(former_employee_email, target_email),
        former_employee_number = COALESCE(former_employee_number, target_profile.emp_index::TEXT),
        employee_id = NULL, updated_at = NOW()
    WHERE employee_id = target_user_id;
    GET DIAGNOSTICS archived_count = ROW_COUNT;

    FOR ref IN
        SELECT DISTINCT cols.table_schema, cols.table_name, cols.column_name
        FROM information_schema.columns cols
        JOIN information_schema.tables tbl
          ON tbl.table_schema = cols.table_schema AND tbl.table_name = cols.table_name
        WHERE cols.table_schema = 'public' AND tbl.table_type = 'BASE TABLE'
          AND cols.table_name NOT IN ('profiles', 'contracts')
          AND cols.column_name IN ('employee_id','user_id','created_by','admin_id','sender_id','receiver_id','assignee_id','supervisor_id','approver_id','actor_id','actor_user_id','target_user_id','assigned_to','owner_id')
          AND cols.data_type = 'uuid'
    LOOP
        EXECUTE format('DELETE FROM %I.%I WHERE %I = $1', ref.table_schema, ref.table_name, ref.column_name) USING target_user_id;
    END LOOP;

    -- Clear remaining nullable references (manager/head relationships), and
    -- remove rows whose required foreign key still points at this employee.
    FOR ref IN
        SELECT ns.nspname table_schema, rel.relname table_name, att.attname column_name, att.attnotnull is_required
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = rel.relnamespace
        JOIN pg_class parent_rel ON parent_rel.oid = con.confrelid
        JOIN pg_namespace parent_ns ON parent_ns.oid = parent_rel.relnamespace
        JOIN unnest(con.conkey) AS key(attnum) ON TRUE
        JOIN pg_attribute att ON att.attrelid = rel.oid AND att.attnum = key.attnum
        WHERE con.contype = 'f' AND ns.nspname = 'public'
          AND NOT (rel.relname = 'contracts' AND att.attname = 'employee_id')
          AND ((parent_ns.nspname = 'public' AND parent_rel.relname = 'profiles')
            OR (parent_ns.nspname = 'auth' AND parent_rel.relname = 'users'))
    LOOP
        IF ref.is_required THEN
            EXECUTE format('DELETE FROM %I.%I WHERE %I = $1', ref.table_schema, ref.table_name, ref.column_name) USING target_user_id;
        ELSE
            EXECUTE format('UPDATE %I.%I SET %I = NULL WHERE %I = $1', ref.table_schema, ref.table_name, ref.column_name, ref.column_name) USING target_user_id;
        END IF;
    END LOOP;

    DELETE FROM public.profiles WHERE id = target_user_id;
    DELETE FROM auth.users WHERE id = target_user_id;
    RETURN jsonb_build_object('success', TRUE, 'archived_contracts', archived_count);
END; $$;

REVOKE ALL ON FUNCTION public.archive_and_delete_employee(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_and_delete_employee(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_archived_contract(target_contract_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND UPPER(COALESCE(role, '')) = 'ADMIN') THEN
        RAISE EXCEPTION 'Only an administrator can permanently delete archived contracts';
    END IF;
    DELETE FROM public.contracts WHERE id = target_contract_id AND is_archived = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Archived contract not found'; END IF;
END; $$;

REVOKE ALL ON FUNCTION public.delete_archived_contract(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_archived_contract(UUID) TO authenticated;

DROP POLICY IF EXISTS "Archived contracts are visible to contract managers" ON public.contracts;
CREATE POLICY "Archived contracts are visible to contract managers" ON public.contracts FOR SELECT USING (
    is_archived = TRUE AND EXISTS (
        SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_active IS DISTINCT FROM FALSE
          AND (UPPER(COALESCE(role, '')) = 'ADMIN' OR UPPER(COALESCE(job_title, '')) = 'HR MANAGER')
    )
);
