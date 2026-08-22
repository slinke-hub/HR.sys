-- The 30-day notification flag remains available to automation but is not a
-- user-facing directory column.
BEGIN;
COMMENT ON COLUMN public.employee_documents.notified_30_days IS
  'Internal expiry-notification automation flag. Hidden from the employee document directory UI.';
NOTIFY pgrst,'reload schema';
COMMIT;
