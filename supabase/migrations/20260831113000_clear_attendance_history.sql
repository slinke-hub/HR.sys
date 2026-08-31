-- Clear all clock-in and clock-out history without removing employee accounts.
BEGIN;

TRUNCATE TABLE
    public.attendance,
    public.time_punches
RESTART IDENTITY CASCADE;

COMMIT;
