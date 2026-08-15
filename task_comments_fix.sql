-- 1. Drop existing foreign key constraint if it exists (it might be named differently, so we check)
DO $$
DECLARE
    fk_name text;
BEGIN
    SELECT conname INTO fk_name
    FROM pg_constraint
    WHERE conrelid = 'task_comments'::regclass
      AND confrelid = 'auth.users'::regclass;
      
    IF fk_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE task_comments DROP CONSTRAINT ' || fk_name;
    END IF;
END $$;

-- 2. Add foreign key to profiles
ALTER TABLE task_comments
ADD CONSTRAINT fk_task_comments_profiles 
FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- 3. Enable RLS
ALTER TABLE task_comments ENABLE ROW LEVEL SECURITY;

-- 4. Drop old policies (if they exist)
DROP POLICY IF EXISTS "Enable read access for all users" ON task_comments;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON task_comments;

-- 5. Create new comprehensive RLS policies
CREATE POLICY "Enable read access for all users" 
ON task_comments FOR SELECT 
USING (true);

CREATE POLICY "Enable insert for authenticated users only" 
ON task_comments FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Enable update for users based on user_id" 
ON task_comments FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Enable delete for users based on user_id" 
ON task_comments FOR DELETE 
USING (auth.uid() = user_id);
