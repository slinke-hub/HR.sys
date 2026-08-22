-- Store verified device coordinates when an employee clocks out from an order location.
ALTER TABLE public.attendance
    ADD COLUMN IF NOT EXISTS order_location_latitude NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS order_location_longitude NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS order_location_accuracy NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS order_location_shared_at TIMESTAMPTZ;

ALTER TABLE public.attendance
    DROP CONSTRAINT IF EXISTS attendance_order_location_required;

ALTER TABLE public.attendance
    ADD CONSTRAINT attendance_order_location_required CHECK (
        clock_out_type IS DISTINCT FROM 'ORDER'
        OR (
            order_location_latitude IS NOT NULL
            AND order_location_longitude IS NOT NULL
            AND order_location_shared_at IS NOT NULL
        )
    ) NOT VALID;

-- Existing historical ORDER rows are left intact; the constraint applies to
-- all new and updated rows without requiring fabricated legacy coordinates.

NOTIFY pgrst, 'reload schema';
