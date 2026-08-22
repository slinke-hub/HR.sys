-- Non-recursive authorization shared by onboarding profile, contract and file writes.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS nationality VARCHAR(30) DEFAULT 'Saudi';
ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES public.departments(id),
    ADD COLUMN IF NOT EXISTS primary_workplace VARCHAR(255),
    ADD COLUMN IF NOT EXISTS weekly_rest_day VARCHAR(100) DEFAULT 'Friday, Saturday',
    ADD COLUMN IF NOT EXISTS confidentiality_policy_url TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('contract-documents', 'contract-documents', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

CREATE OR REPLACE FUNCTION public.can_manage_employee_contracts(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = p_user_id
          AND is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(COALESCE(role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN')
              OR UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_manage_employee_contracts(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_employee_contracts(UUID) TO authenticated;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Contract managers can update employee profiles" ON public.profiles;
CREATE POLICY "Contract managers can update employee profiles"
ON public.profiles
FOR UPDATE
TO authenticated
USING (public.can_manage_employee_contracts(auth.uid()))
WITH CHECK (public.can_manage_employee_contracts(auth.uid()));

-- Preserve protected profile fields while allowing HR Managers to synchronize
-- only the employment fields sourced from a saved contract.
CREATE OR REPLACE FUNCTION public.protect_profile_privileged_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    caller_role TEXT;
    caller_job_title TEXT;
    employee_editable_fields TEXT[] := ARRAY[
        'full_name','display_name','iqama_number','phone_number','avatar_url','last_login','birth_date'
    ];
    hr_editable_fields TEXT[] := ARRAY[
        'full_name','display_name','iqama_number','phone_number','avatar_url','last_login','birth_date',
        'job_title','department_id','base_salary','nationality','role'
    ];
BEGIN
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    SELECT UPPER(COALESCE(role, '')), UPPER(COALESCE(job_title, ''))
      INTO caller_role, caller_job_title
      FROM public.profiles
     WHERE id = auth.uid();

    IF caller_role IN ('ADMIN', 'ROLE_SYSTEM_ADMIN') THEN RETURN NEW; END IF;

    IF caller_job_title = 'HR MANAGER' THEN
        IF (to_jsonb(NEW) - hr_editable_fields) IS DISTINCT FROM (to_jsonb(OLD) - hr_editable_fields) THEN
            RAISE EXCEPTION 'HR Manager can only change contract-synchronized employment fields' USING ERRCODE = '42501';
        END IF;
        RETURN NEW;
    END IF;

    IF (to_jsonb(NEW) - employee_editable_fields) IS DISTINCT FROM (to_jsonb(OLD) - employee_editable_fields) THEN
        RAISE EXCEPTION 'Only an administrator can change protected profile fields' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Contract managers can manage contracts" ON public.contracts;
CREATE POLICY "Contract managers can manage contracts"
ON public.contracts
FOR ALL
TO authenticated
USING (public.can_manage_employee_contracts(auth.uid()))
WITH CHECK (public.can_manage_employee_contracts(auth.uid()));

DROP POLICY IF EXISTS "Contract managers can upload contract documents" ON storage.objects;
CREATE POLICY "Contract managers can upload contract documents"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'contract-documents'
    AND public.can_manage_employee_contracts(auth.uid())
);

DROP POLICY IF EXISTS "Contract managers can update contract documents" ON storage.objects;
CREATE POLICY "Contract managers can update contract documents"
ON storage.objects
FOR UPDATE
TO authenticated
USING (bucket_id = 'contract-documents' AND public.can_manage_employee_contracts(auth.uid()))
WITH CHECK (bucket_id = 'contract-documents' AND public.can_manage_employee_contracts(auth.uid()));
