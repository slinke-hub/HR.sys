-- Restrict Payroll Workflow to Finance Manager and system administrators.
BEGIN;
CREATE OR REPLACE FUNCTION public.is_payroll_manager(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.profiles profile WHERE profile.id=p_user_id AND (
      upper(COALESCE(profile.role,'')) IN('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
      OR upper(BTRIM(COALESCE(profile.job_title,'')))='FINANCE MANAGER'
    )
  );
$$;
REVOKE ALL ON FUNCTION public.is_payroll_manager(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_payroll_manager(UUID) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
