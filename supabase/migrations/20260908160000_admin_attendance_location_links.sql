-- Keep employee punches tied to captured GPS coordinates while allowing an
-- administrator to replace a punch location with a Google Maps link.
BEGIN;

CREATE OR REPLACE FUNCTION public.is_valid_google_maps_location(candidate TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT BTRIM(COALESCE(candidate, '')) ~* '^https?://((www\.)?maps\.app\.goo\.gl|((www\.)?goo\.gl/maps)|maps\.google\.[a-z.]+|(([a-z0-9-]+\.)?google\.[a-z.]+/maps))([/?#]|$)';
$$;

REVOKE ALL ON FUNCTION public.is_valid_google_maps_location(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_valid_google_maps_location(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_valid_google_maps_location(TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.enforce_attendance_coordinates()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    manager_is_saving_map_link BOOLEAN := public.can_manage_attendance_records(auth.uid());
BEGIN
    IF (TG_OP = 'INSERT' OR NEW.clock_in_time IS DISTINCT FROM OLD.clock_in_time OR NEW.clock_in_location IS DISTINCT FROM OLD.clock_in_location)
       AND NEW.clock_in_time IS NOT NULL
       AND NOT public.is_valid_attendance_coordinates(NEW.clock_in_location)
       AND NOT (manager_is_saving_map_link AND public.is_valid_google_maps_location(NEW.clock_in_location)) THEN
        RAISE EXCEPTION 'Clock-in requires captured coordinates or an administrator Google Maps link' USING ERRCODE = '23514';
    END IF;
    IF (TG_OP = 'INSERT' OR NEW.clock_out_time IS DISTINCT FROM OLD.clock_out_time OR NEW.clock_out_location IS DISTINCT FROM OLD.clock_out_location)
       AND NEW.clock_out_time IS NOT NULL
       AND NOT public.is_valid_attendance_coordinates(NEW.clock_out_location)
       AND NOT (manager_is_saving_map_link AND public.is_valid_google_maps_location(NEW.clock_out_location)) THEN
        RAISE EXCEPTION 'Clock-out requires captured coordinates or an administrator Google Maps link' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
