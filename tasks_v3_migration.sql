-- ==============================================================================
-- Tasks V3 Migration (Advanced Fields & Comments)
-- Adds start/end dates, estimates, visibility to tasks.
-- Creates the task_comments table.
-- ==============================================================================

-- 1. Add new fields to tasks
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS start_date DATE;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS end_date DATE;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS estimated_time VARCHAR(100);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS visibility VARCHAR(20) DEFAULT 'public' CHECK (visibility IN ('public', 'private', 'team'));

-- 2. Create task_comments table
CREATE TABLE IF NOT EXISTS task_comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Note: Ensure Row Level Security (RLS) is disabled or correctly configured for task_comments if used in Supabase.
