-- Store the coordinates captured at clock-in and clock-out so attendance
-- history can provide a direct Google Maps link.

BEGIN;

ALTER TABLE public.attendance
  ADD COLUMN IF NOT EXISTS clock_in_location text,
  ADD COLUMN IF NOT EXISTS clock_out_location text;

GRANT SELECT, INSERT, UPDATE ON public.attendance TO authenticated;
NOTIFY pgrst, 'reload schema';

COMMIT;
