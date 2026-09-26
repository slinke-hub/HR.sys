-- ==============================================================================
-- ENTERPRISE HR SUITE FEATURES MIGRATION
-- Adds schema for ATS, Expenses, LMS, Performance, Surveys, and Shifts.
-- ==============================================================================

-- ==========================================
-- 1. Recruitment & ATS
-- ==========================================
CREATE TABLE IF NOT EXISTS public.jobs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    department_id UUID REFERENCES public.departments(id),
    status VARCHAR(50) DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'CLOSED', 'DRAFT')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage jobs" ON public.jobs USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));
CREATE POLICY "Everyone views open jobs" ON public.jobs FOR SELECT USING (true);

CREATE TABLE IF NOT EXISTS public.candidates (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    job_id UUID REFERENCES public.jobs(id),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(50),
    resume_url TEXT,
    status VARCHAR(50) DEFAULT 'APPLIED' CHECK (status IN ('APPLIED', 'SCREENING', 'INTERVIEW', 'OFFERED', 'HIRED', 'REJECTED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.candidates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage candidates" ON public.candidates USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));


-- ==========================================
-- 2. Expense Management
-- ==========================================
CREATE TABLE IF NOT EXISTS public.expense_claims (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    amount DECIMAL(10, 2) NOT NULL,
    category VARCHAR(100),
    description TEXT,
    receipt_url TEXT,
    status VARCHAR(50) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'PAID')),
    approved_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.expense_claims ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees view own expenses" ON public.expense_claims FOR SELECT USING (auth.uid() = employee_id);
CREATE POLICY "Employees insert own expenses" ON public.expense_claims FOR INSERT WITH CHECK (auth.uid() = employee_id);
CREATE POLICY "Admins and Managers view and update expenses" ON public.expense_claims USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));


-- ==========================================
-- 3. Learning Management System (LMS)
-- ==========================================
CREATE TABLE IF NOT EXISTS public.training_courses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    is_mandatory BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.training_courses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage courses" ON public.training_courses USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));
CREATE POLICY "Everyone views courses" ON public.training_courses FOR SELECT USING (true);

CREATE TABLE IF NOT EXISTS public.employee_training (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    course_id UUID REFERENCES public.training_courses(id),
    status VARCHAR(50) DEFAULT 'ENROLLED' CHECK (status IN ('ENROLLED', 'IN_PROGRESS', 'COMPLETED')),
    completion_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.employee_training ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees manage own training" ON public.employee_training USING (auth.uid() = employee_id);
CREATE POLICY "Admins view all training" ON public.employee_training FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));


-- ==========================================
-- 4. Advanced Performance & Appraisals
-- ==========================================
CREATE TABLE IF NOT EXISTS public.performance_reviews (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    reviewer_id UUID NOT NULL REFERENCES auth.users(id),
    review_period VARCHAR(50),
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    comments TEXT,
    status VARCHAR(50) DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PUBLISHED', 'ACKNOWLEDGED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.performance_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view their own reviews" ON public.performance_reviews FOR SELECT USING (auth.uid() = employee_id OR auth.uid() = reviewer_id);
CREATE POLICY "Admins manage reviews" ON public.performance_reviews USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));
CREATE POLICY "Reviewers update their reviews" ON public.performance_reviews FOR UPDATE USING (auth.uid() = reviewer_id);

CREATE TABLE IF NOT EXISTS public.goals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    progress INTEGER DEFAULT 0 CHECK (progress >= 0 AND progress <= 100),
    target_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees manage own goals" ON public.goals USING (auth.uid() = employee_id);
CREATE POLICY "Admins/Managers view goals" ON public.goals FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));


-- ==========================================
-- 5. Employee Engagement & Pulse Surveys
-- ==========================================
CREATE TABLE IF NOT EXISTS public.surveys (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.surveys ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage surveys" ON public.surveys USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));
CREATE POLICY "Everyone views surveys" ON public.surveys FOR SELECT USING (true);

CREATE TABLE IF NOT EXISTS public.survey_responses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    survey_id UUID REFERENCES public.surveys(id),
    employee_id UUID REFERENCES auth.users(id), -- Nullable for anonymity
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.survey_responses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees insert responses" ON public.survey_responses FOR INSERT WITH CHECK (auth.uid() = employee_id OR employee_id IS NULL);
CREATE POLICY "Admins view responses" ON public.survey_responses FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

CREATE TABLE IF NOT EXISTS public.recognitions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    from_employee_id UUID NOT NULL REFERENCES auth.users(id),
    to_employee_id UUID NOT NULL REFERENCES auth.users(id),
    message TEXT NOT NULL,
    points INTEGER DEFAULT 10,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.recognitions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Everyone views recognitions" ON public.recognitions FOR SELECT USING (true);
CREATE POLICY "Employees give recognition" ON public.recognitions FOR INSERT WITH CHECK (auth.uid() = from_employee_id);


-- ==========================================
-- 6. Advanced Shift & Schedule Planning
-- ==========================================
CREATE TABLE IF NOT EXISTS public.shifts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    employee_id UUID NOT NULL REFERENCES auth.users(id),
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE NOT NULL,
    location VARCHAR(255),
    role VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Employees view own shifts" ON public.shifts FOR SELECT USING (auth.uid() = employee_id);
CREATE POLICY "Admins/Managers manage shifts" ON public.shifts USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')));
