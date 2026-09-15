-- Drop the existing policy to replace it
DROP POLICY IF EXISTS "Admins can delete projects" ON public.projects;
DROP POLICY IF EXISTS "Sales and Marketing can delete projects" ON public.projects;
DROP POLICY IF EXISTS "Admins, Sales and Marketing can delete projects" ON public.projects;

-- Create the new policy allowing Admins, Sales, and Marketing departments to delete projects
CREATE POLICY "Admins, Sales and Marketing can delete projects" 
ON public.projects 
FOR DELETE 
USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        LEFT JOIN public.departments ON profiles.department_id = departments.id
        WHERE profiles.id = auth.uid() 
        AND (
            profiles.role ILIKE '%ADMIN%' OR 
            profiles.role ILIKE '%SALES%' OR profiles.role ILIKE '%MARKETING%' OR
            profiles.job_title ILIKE '%SALES%' OR profiles.job_title ILIKE '%MARKETING%' OR
            profiles.role ILIKE '%مبيعات%' OR profiles.role ILIKE '%تسويق%' OR
            profiles.job_title ILIKE '%مبيعات%' OR profiles.job_title ILIKE '%تسويق%' OR
            departments.name ILIKE '%sales%' OR departments.name ILIKE '%marketing%' OR
            departments.name ILIKE '%مبيعات%' OR departments.name ILIKE '%تسويق%'
        )
    )
);
