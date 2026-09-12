-- Migration: Create task_comments table with attachments support, RLS policies, and notification trigger
BEGIN;

-- 1. Create table public.task_comments
CREATE TABLE IF NOT EXISTS public.task_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES public.task_comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    attachments JSONB NOT NULL DEFAULT '[]'::JSONB,
    edited_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure attachments column exists if table was created previously without it
ALTER TABLE public.task_comments
    ADD COLUMN IF NOT EXISTS attachments JSONB NOT NULL DEFAULT '[]'::JSONB;

ALTER TABLE public.task_comments
    ADD COLUMN IF NOT EXISTS parent_comment_id UUID REFERENCES public.task_comments(id) ON DELETE CASCADE;

ALTER TABLE public.task_comments
    ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

-- 2. Create indexes
CREATE INDEX IF NOT EXISTS task_comments_task_id_idx ON public.task_comments(task_id, created_at);
CREATE INDEX IF NOT EXISTS task_comments_user_id_idx ON public.task_comments(user_id);

-- 3. Enable RLS and configure policies
ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Enable read access for all users" ON public.task_comments;
DROP POLICY IF EXISTS "task_comments_select" ON public.task_comments;
CREATE POLICY "task_comments_select"
    ON public.task_comments FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.task_comments;
DROP POLICY IF EXISTS "task_comments_insert" ON public.task_comments;
CREATE POLICY "task_comments_insert"
    ON public.task_comments FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Enable update for users based on user_id" ON public.task_comments;
DROP POLICY IF EXISTS "task_comments_update" ON public.task_comments;
CREATE POLICY "task_comments_update"
    ON public.task_comments FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON public.task_comments;
DROP POLICY IF EXISTS "task_comments_delete" ON public.task_comments;
CREATE POLICY "task_comments_delete"
    ON public.task_comments FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- 4. Permissions
GRANT ALL ON TABLE public.task_comments TO authenticated, service_role;

-- 5. Trigger for automatic email & in-app notifications on comment
CREATE OR REPLACE FUNCTION public.notify_task_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'queue_task_notification') THEN
        PERFORM public.queue_task_notification(
            NEW.task_id,
            NEW.user_id,
            'task_comment',
            'New comment on task'
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_task_comment_trigger ON public.task_comments;
CREATE TRIGGER notify_task_comment_trigger
    AFTER INSERT ON public.task_comments
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_task_comment();

-- 6. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
