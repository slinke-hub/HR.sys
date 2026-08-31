-- Reset annual leave usage for every employee.
-- Leave balances are derived from leave_requests, so removing the requests
-- restores each profile's full configured allowance without changing users or
-- annual_leave_allowance values.
BEGIN;

TRUNCATE TABLE public.leave_requests
RESTART IDENTITY CASCADE;

COMMIT;
