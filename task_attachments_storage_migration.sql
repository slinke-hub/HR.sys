-- Public task attachment bucket. Uploads are namespaced by task and uploader.
INSERT INTO storage.buckets (id, name, public)
VALUES ('task-attachments', 'task-attachments', TRUE)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DROP POLICY IF EXISTS "Authenticated users can upload task attachments" ON storage.objects;
CREATE POLICY "Authenticated users can upload task attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'task-attachments'
    AND (storage.foldername(name))[2] = auth.uid()::text
);

DROP POLICY IF EXISTS "Authenticated users can read task attachments" ON storage.objects;
CREATE POLICY "Authenticated users can read task attachments"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'task-attachments');

DROP POLICY IF EXISTS "Uploaders can update task attachments" ON storage.objects;
CREATE POLICY "Uploaders can update task attachments"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'task-attachments' AND (storage.foldername(name))[2] = auth.uid()::text)
WITH CHECK (bucket_id = 'task-attachments' AND (storage.foldername(name))[2] = auth.uid()::text);

DROP POLICY IF EXISTS "Uploaders can delete task attachments" ON storage.objects;
CREATE POLICY "Uploaders can delete task attachments"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'task-attachments' AND (storage.foldername(name))[2] = auth.uid()::text);
