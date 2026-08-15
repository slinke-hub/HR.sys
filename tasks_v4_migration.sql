-- ==============================================================================
-- Tasks V4 Migration (Projects, Approval Workflow, Visibility)
-- ==============================================================================

-- 1. Create Projects Table
CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_name VARCHAR(255) NOT NULL,
    project_type VARCHAR(255) NOT NULL,
    description TEXT,
    assigned_people UUID[],
    project_category VARCHAR(50) CHECK (project_category IN ('Startup', 'Enterprise')),
    project_tags TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on Projects
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view projects they are assigned to or if they are admin" ON projects FOR SELECT USING (
    auth.uid() = ANY(assigned_people) 
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN')
);
CREATE POLICY "Admins can insert projects" ON projects FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN')
);
CREATE POLICY "Admins can update projects" ON projects FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN')
);

-- 2. Add New Columns to Tasks Table
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS project_id UUID REFERENCES projects(id) ON DELETE SET NULL;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS tags TEXT[];
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS attachments JSONB DEFAULT '[]'::jsonb;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS visible_to UUID[];
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS content_type VARCHAR(255);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS source_link TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS upload_link TEXT;

-- 3. Modify Status Constraint
-- PostgreSQL requires dropping the existing check constraint before adding a new one.
-- First, find the constraint name for the status column on tasks table (usually tasks_status_check).
-- Since we might not know the exact system-generated name, we use an anonymous PL/pgSQL block to drop it dynamically if it exists.
DO $$
DECLARE
    constraint_name text;
BEGIN
    SELECT conname INTO constraint_name
    FROM pg_constraint
    WHERE conrelid = 'tasks'::regclass AND contype = 'c' AND pg_get_expr(conbin, conrelid) ILIKE '%status%';
    
    IF constraint_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE tasks DROP CONSTRAINT ' || constraint_name;
    END IF;
END $$;

-- Add new constraint
ALTER TABLE tasks ADD CONSTRAINT tasks_status_check CHECK (status IN ('todo', 'in_progress', 'review', 'completed', 'Pending Approval', 'Approved', 'Rejected'));

-- 4. Update Task RLS Policy to respect visible_to
-- We need to drop existing select policy and replace it.
DROP POLICY IF EXISTS "Users can view tasks assigned to them" ON tasks;
CREATE POLICY "Users can view tasks assigned to them or if in visible_to" ON tasks FOR SELECT USING (
    auth.uid() = assignee_id 
    OR auth.uid() = created_by 
    OR auth.uid() = ANY(visible_to)
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN')
);
