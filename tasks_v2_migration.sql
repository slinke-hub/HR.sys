-- ==============================================================================
-- Tasks V2 Migration
-- Updates the existing tasks table to support multi-language, priority, category,
-- and the requested kanban status workflow.
-- ==============================================================================

-- 1. Add priority and category columns
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent'));
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS category VARCHAR(50) DEFAULT 'Work';

-- 2. Add JSONB columns for translations (Record<string, string>)
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS title_i18n JSONB DEFAULT '{}'::jsonb;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS description_i18n JSONB DEFAULT '{}'::jsonb;

-- 3. Add updated_at timestamp
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- 4. Update the status check constraint to support Kanban board statuses
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_status_check;

-- Map any existing old statuses to the new format
UPDATE tasks SET status = 'todo' WHERE status = 'TODO';
UPDATE tasks SET status = 'in_progress' WHERE status = 'IN_PROGRESS';
UPDATE tasks SET status = 'completed' WHERE status = 'DONE';
UPDATE tasks SET status = 'todo' WHERE status IS NULL;

-- Apply new constraint
ALTER TABLE tasks ADD CONSTRAINT tasks_status_check CHECK (status IN ('todo', 'in_progress', 'review', 'completed'));

-- 5. Trigger for updated_at (optional if your DB supports it, else handle in JS)
-- Create a basic function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_tasks_updated_at ON tasks;
CREATE TRIGGER update_tasks_updated_at
BEFORE UPDATE ON tasks
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
