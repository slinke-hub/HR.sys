-- Synchronize contract identity details with employee profiles and provide a
-- department-manager approval workflow for employee print requests.

ALTER TABLE public.contracts
    ADD COLUMN IF NOT EXISTS identity_number TEXT,
    ADD COLUMN IF NOT EXISTS employee_phone TEXT;

CREATE OR REPLACE FUNCTION public.sync_contract_identity_to_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.profiles
    SET
        iqama_number = COALESCE(NULLIF(BTRIM(NEW.identity_number), ''), iqama_number),
        phone_number = COALESCE(NULLIF(BTRIM(NEW.employee_phone), ''), phone_number)
    WHERE id = NEW.employee_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS contracts_sync_identity_profile ON public.contracts;
CREATE TRIGGER contracts_sync_identity_profile
AFTER INSERT OR UPDATE OF identity_number, employee_phone ON public.contracts
FOR EACH ROW EXECUTE FUNCTION public.sync_contract_identity_to_profile();

-- Synchronize existing contract data immediately.
UPDATE public.profiles profile
SET
    iqama_number = COALESCE(NULLIF(BTRIM(contract.identity_number), ''), profile.iqama_number),
    phone_number = COALESCE(NULLIF(BTRIM(contract.employee_phone), ''), profile.phone_number)
FROM public.contracts contract
WHERE contract.employee_id = profile.id
  AND contract.is_archived IS DISTINCT FROM TRUE;

CREATE TABLE IF NOT EXISTS public.contract_print_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contract_id UUID NOT NULL REFERENCES public.contracts(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    manager_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    manager_note TEXT,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    decided_at TIMESTAMPTZ
);

ALTER TABLE public.contract_print_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Employees view own contract print requests" ON public.contract_print_requests;
CREATE POLICY "Employees view own contract print requests"
ON public.contract_print_requests FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR manager_id = auth.uid() OR EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND UPPER(COALESCE(p.role, '')) = 'ADMIN'
));

DROP POLICY IF EXISTS "Employees request their own contract print" ON public.contract_print_requests;
CREATE POLICY "Employees request their own contract print"
ON public.contract_print_requests FOR INSERT TO authenticated
WITH CHECK (employee_id = auth.uid() AND status = 'PENDING');

DROP POLICY IF EXISTS "Managers decide contract print requests" ON public.contract_print_requests;
CREATE POLICY "Managers decide contract print requests"
ON public.contract_print_requests FOR UPDATE TO authenticated
USING (manager_id = auth.uid() OR EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND UPPER(COALESCE(p.role, '')) = 'ADMIN'
))
WITH CHECK (manager_id = auth.uid() OR EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND UPPER(COALESCE(p.role, '')) = 'ADMIN'
));

GRANT SELECT, INSERT, UPDATE ON public.contract_print_requests TO authenticated;
CREATE INDEX IF NOT EXISTS contract_print_requests_manager_status_idx
ON public.contract_print_requests(manager_id, status, requested_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS contract_print_requests_one_pending_idx
ON public.contract_print_requests(contract_id, employee_id) WHERE status = 'PENDING';

NOTIFY pgrst, 'reload schema';
