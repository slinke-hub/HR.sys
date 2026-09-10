-- Allow task comments to carry private file and image attachment metadata.
BEGIN;

ALTER TABLE public.task_comments
    ADD COLUMN IF NOT EXISTS attachments JSONB NOT NULL DEFAULT '[]'::JSONB;

ALTER TABLE public.task_comments
    DROP CONSTRAINT IF EXISTS task_comments_attachments_array_check;

ALTER TABLE public.task_comments
    ADD CONSTRAINT task_comments_attachments_array_check
    CHECK (jsonb_typeof(attachments) = 'array');

COMMENT ON COLUMN public.task_comments.attachments IS
    'Private task-attachments storage references with file name, MIME type, and size metadata.';

COMMIT;
