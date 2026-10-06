-- Keep crm_client_dto as an internal helper for owner-executed Client RPCs.
-- This migration changes only direct EXECUTE privileges on its exact signature.
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.crm_client_dto(public.crm_clients)') IS NULL THEN
    RAISE EXCEPTION 'Required internal helper public.crm_client_dto(public.crm_clients) is missing';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.crm_client_dto(public.crm_clients)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
