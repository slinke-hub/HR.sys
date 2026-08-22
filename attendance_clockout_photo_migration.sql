-- Require and securely store a fresh camera photo for order-location clock outs.
ALTER TABLE public.attendance
    ADD COLUMN IF NOT EXISTS order_location_photo_path TEXT;

ALTER TABLE public.attendance
    DROP CONSTRAINT IF EXISTS attendance_order_photo_required;

ALTER TABLE public.attendance
    ADD CONSTRAINT attendance_order_photo_required CHECK (
        clock_out_type IS DISTINCT FROM 'ORDER'
        OR order_location_photo_path IS NOT NULL
    ) NOT VALID;

INSERT INTO storage.buckets (id, name, public)
VALUES ('attendance-clockout-photos', 'attendance-clockout-photos', FALSE)
ON CONFLICT (id) DO UPDATE SET public = FALSE;

DROP POLICY IF EXISTS "Employees upload their clockout photos" ON storage.objects;
CREATE POLICY "Employees upload their clockout photos"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'attendance-clockout-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Employees read their clockout photos" ON storage.objects;
CREATE POLICY "Employees read their clockout photos"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'attendance-clockout-photos'
    AND (
        (storage.foldername(name))[1] = auth.uid()::text
        OR EXISTS (
            SELECT 1 FROM public.profiles viewer
            WHERE viewer.id = auth.uid()
              AND COALESCE(viewer.is_active, TRUE) = TRUE
              AND (
                  UPPER(TRIM(COALESCE(viewer.role, ''))) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
                  OR UPPER(TRIM(COALESCE(viewer.job_title, ''))) = 'HR MANAGER'
              )
        )
    )
);

DROP POLICY IF EXISTS "Employees delete their clockout photos" ON storage.objects;
CREATE POLICY "Employees delete their clockout photos"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'attendance-clockout-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

NOTIFY pgrst, 'reload schema';
