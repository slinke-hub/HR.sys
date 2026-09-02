-- Store repeat settings for daily, weekly and monthly tasks.
BEGIN;
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS repeat_type text NOT NULL DEFAULT 'NONE',
  ADD COLUMN IF NOT EXISTS repeat_interval integer NOT NULL DEFAULT 1;
ALTER TABLE public.tasks
  DROP CONSTRAINT IF EXISTS tasks_repeat_type_check;
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_repeat_type_check CHECK (repeat_type IN ('NONE','DAILY','WEEKLY','MONTHLY'));
ALTER TABLE public.tasks
  DROP CONSTRAINT IF EXISTS tasks_repeat_interval_check;
ALTER TABLE public.tasks
  ADD CONSTRAINT tasks_repeat_interval_check CHECK (repeat_interval > 0);
NOTIFY pgrst, 'reload schema';
COMMIT;
