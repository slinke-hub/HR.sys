-- Create role_permissions table
CREATE TABLE IF NOT EXISTS public.role_permissions (
    role VARCHAR PRIMARY KEY,
    allowed_pages JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

-- Policies for role_permissions
-- Everyone authenticated can read
CREATE POLICY "Allow authenticated users to read role permissions" 
    ON public.role_permissions 
    FOR SELECT 
    USING (auth.role() = 'authenticated');

-- Only admins can insert/update/delete
CREATE POLICY "Allow admins to modify role permissions" 
    ON public.role_permissions 
    FOR ALL 
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid()
            AND (profiles.role IN ('ADMIN', 'SYSTEM ADMIN', 'OWNER'))
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = auth.uid()
            AND (profiles.role IN ('ADMIN', 'SYSTEM ADMIN', 'OWNER'))
        )
    );

-- Insert default roles
INSERT INTO public.role_permissions (role, allowed_pages) VALUES
    ('EMPLOYEE', '["dashboard", "requests", "time", "tasks", "documents", "profile"]'),
    ('MANAGER', '["dashboard", "requests", "time", "tasks", "documents", "profile", "approvals"]'),
    ('HR_MANAGER', '["dashboard", "requests", "time", "tasks", "documents", "profile", "approvals", "leave_calculator", "employees", "custody_handover"]'),
    ('ADMIN', '["dashboard", "tasks", "requests", "time", "documents", "expenses", "performance", "projects", "crm", "clients", "approvals", "profile", "notifications", "admin", "users", "departments", "translations", "templates", "analytics", "leave_calculator", "employees", "custody_handover", "payroll"]')
ON CONFLICT (role) DO UPDATE SET allowed_pages = EXCLUDED.allowed_pages;
