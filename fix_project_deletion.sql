-- Fix for Project Deletion silently failing due to RLS policies

-- 1. Ensure the DELETE policy exists for the projects table so Admins can delete projects.
DROP POLICY IF EXISTS "Admins can delete projects" ON public.projects;
CREATE POLICY "Admins can delete projects" 
ON public.projects 
FOR DELETE 
USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'ADMIN'
    )
);

-- 2. Optional: If users who created the project should also be able to delete it
DROP POLICY IF EXISTS "Creators can delete their projects" ON public.projects;
CREATE POLICY "Creators can delete their projects" 
ON public.projects 
FOR DELETE 
USING (
    creator_id = auth.uid()
);

-- Note: If you have foreign key constraints from tasks to projects, 
-- you may also need to update those to ON DELETE CASCADE if you want 
-- to delete a project that already has tasks assigned to it.
