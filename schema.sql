-- Supabase Schema for Aegis HR

-- 1. Time Punches Table
CREATE TABLE time_punches (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    employee_id UUID NOT NULL, -- References auth.users(id) in a real setup
    punch_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    punch_type VARCHAR(10) CHECK (punch_type IN ('IN', 'OUT')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS (Row Level Security)
ALTER TABLE time_punches ENABLE ROW LEVEL SECURITY;

-- Allow anonymous inserts for the prototype
CREATE POLICY "Allow anonymous inserts" ON time_punches
    FOR INSERT WITH CHECK (true);

-- Allow anonymous selects for the prototype
CREATE POLICY "Allow anonymous selects" ON time_punches
    FOR SELECT USING (true);


-- 2. Leave Requests Table
CREATE TABLE leave_requests (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    employee_id UUID NOT NULL,
    leave_type VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow anonymous inserts" ON leave_requests FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow anonymous selects" ON leave_requests FOR SELECT USING (true);


-- 3. Announcements Table
CREATE TABLE announcements (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    icon VARCHAR(50) DEFAULT 'megaphone',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow anonymous selects" ON announcements FOR SELECT USING (true);

-- Insert dummy announcements
INSERT INTO announcements (title, content, icon) VALUES 
('Q3 Townhall Meeting', 'Join us this Friday for the quarterly company update. Location: Main Auditorium & Zoom.', 'megaphone'),
('New Wellness Benefits Added', 'We have added gym memberships to our health coverage. Check your benefits portal.', 'heart-pulse');
