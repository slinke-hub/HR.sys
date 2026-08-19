-- ========================================================
-- MIGRATION: ADD SUB-TASKS SUPPORT
-- ========================================================

ALTER TABLE public.tasks 
ADD COLUMN IF NOT EXISTS parent_task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE;
