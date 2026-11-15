-- Only the Storage authorization relation/policy exported from reviewed Staging
-- and Production evidence. It is a synthetic, disposable catalog fixture.
CREATE SCHEMA storage;
CREATE TABLE storage.objects(id uuid PRIMARY KEY, bucket_id text, name text);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT SELECT ON storage.objects TO authenticated;
GRANT SELECT ON storage.objects TO service_role;
CREATE POLICY sensitive_task_attachments_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id='task-attachments' AND public.can_read_task_attachment_file(name,auth.uid()));
