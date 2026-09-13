-- Create user_permissions table
CREATE TABLE IF NOT EXISTS public.user_permissions (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    allowed_pages JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;

-- Policies for user_permissions
-- Everyone authenticated can read their own permissions
CREATE POLICY "Allow authenticated users to read their own permissions" 
    ON public.user_permissions 
    FOR SELECT 
    USING (auth.uid() = user_id OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE profiles.id = auth.uid()
        AND (profiles.role IN ('ADMIN', 'SYSTEM ADMIN', 'OWNER'))
    ));

-- Only admins can insert/update/delete
CREATE POLICY "Allow admins to modify user permissions" 
    ON public.user_permissions 
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
