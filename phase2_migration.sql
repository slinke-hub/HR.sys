-- PHASE 2 MIGRATION SCRIPT

-- 1. Alters to existing tables
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS last_login TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS birth_date DATE;

ALTER TABLE public.employee_documents
ADD COLUMN IF NOT EXISTS expiration_date DATE;

-- 2. Attendance Table
CREATE TABLE IF NOT EXISTS public.attendance (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    clock_in_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    clock_out_time TIMESTAMP WITH TIME ZONE,
    clock_in_location TEXT, -- e.g. "lat,lng" or JSON string
    clock_out_location TEXT,
    clock_out_type VARCHAR(50) CHECK (clock_out_type IN ('OFFICE', 'ORDER')),
    overtime_hours DECIMAL(5,2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees can view own attendance" ON public.attendance FOR SELECT USING (auth.uid() = employee_id);
CREATE POLICY "Employees can insert own attendance" ON public.attendance FOR INSERT WITH CHECK (auth.uid() = employee_id);
CREATE POLICY "Employees can update own attendance" ON public.attendance FOR UPDATE USING (auth.uid() = employee_id);
CREATE POLICY "Admins/Managers can view all attendance" ON public.attendance FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER', 'SUPERVISOR')));

-- 3. Announcements Table
CREATE TABLE IF NOT EXISTS public.announcements (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    admin_id UUID NOT NULL REFERENCES auth.users(id),
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view announcements" ON public.announcements FOR SELECT USING (true);
CREATE POLICY "Only admins can insert announcements" ON public.announcements FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- 4. Community Chat Table
CREATE TABLE IF NOT EXISTS public.community_chat (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    message TEXT NOT NULL,
    is_birthday_alert BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.community_chat ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view chat" ON public.community_chat FOR SELECT USING (true);
CREATE POLICY "Anyone can post in chat" ON public.community_chat FOR INSERT WITH CHECK (auth.uid() = user_id);
