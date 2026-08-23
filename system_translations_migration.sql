-- Supabase Migration: System Translations
-- Creates a table for centralized translations with realtime support and Row Level Security.

CREATE TABLE IF NOT EXISTS system_translations (
    trans_key VARCHAR(255) PRIMARY KEY,
    trans_en TEXT,
    trans_ar TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Realtime for the system_translations table
-- NOTE: In Supabase, you may also need to manually enable Realtime for this table via the Dashboard (Database -> Replication)
alter publication supabase_realtime add table system_translations;

-- Enable Row Level Security (RLS)
ALTER TABLE system_translations ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can read translations
CREATE POLICY "Anyone can view translations" ON system_translations
    FOR SELECT USING (true);

-- Policy: Only Admins can insert translations
CREATE POLICY "Admins can insert translations" ON system_translations
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() AND role = 'ADMIN'
        )
    );

-- Policy: Only Admins can update translations
CREATE POLICY "Admins can update translations" ON system_translations
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() AND role = 'ADMIN'
        )
    );

-- Policy: Only Admins can delete translations
CREATE POLICY "Admins can delete translations" ON system_translations
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE id = auth.uid() AND role = 'ADMIN'
        )
    );
