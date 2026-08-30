-- Allow a task to have one primary assignee plus additional assignees.
-- The existing assignee_id remains the primary assignee for compatibility.
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS assignee_ids uuid[] NOT NULL DEFAULT '{}';

UPDATE public.tasks
SET assignee_ids = ARRAY[assignee_id]::uuid[]
WHERE assignee_id IS NOT NULL
  AND (assignee_ids IS NULL OR cardinality(assignee_ids) = 0);

GRANT SELECT, UPDATE ON public.tasks TO authenticated;
NOTIFY pgrst, 'reload schema';
