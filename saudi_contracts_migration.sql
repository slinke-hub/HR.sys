-- Create establishment_settings table
CREATE TABLE IF NOT EXISTS public.establishment_settings (
    id SERIAL PRIMARY KEY,
    employer_name_ar VARCHAR(255) DEFAULT 'اسم المنشأة',
    employer_name_en VARCHAR(255) DEFAULT 'Establishment Name',
    commercial_registration VARCHAR(50),
    unified_establishment_number VARCHAR(50),
    employer_address TEXT,
    employer_city VARCHAR(100),
    employer_region VARCHAR(100),
    authorized_rep_name VARCHAR(255),
    authorized_rep_title VARCHAR(255),
    employer_contact_details TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default establishment settings if empty
INSERT INTO public.establishment_settings (id, employer_name_en)
SELECT 1, 'Default Establishment'
WHERE NOT EXISTS (SELECT 1 FROM public.establishment_settings WHERE id = 1);

-- Create contract_settings table for statutory limits
CREATE TABLE IF NOT EXISTS public.contract_settings (
    id SERIAL PRIMARY KEY,
    max_probation_days INTEGER DEFAULT 180,
    default_notice_period_days INTEGER DEFAULT 60,
    default_currency VARCHAR(10) DEFAULT 'SAR',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default contract settings if empty
INSERT INTO public.contract_settings (id)
SELECT 1
WHERE NOT EXISTS (SELECT 1 FROM public.contract_settings WHERE id = 1);

-- Create audit_logs table
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id),
    entity_type VARCHAR(100) NOT NULL, -- e.g., 'contract'
    entity_id UUID NOT NULL,
    action VARCHAR(100) NOT NULL, -- e.g., 'created', 'status_changed'
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Modify contracts table to support Saudi Labor Law requirements
ALTER TABLE public.contracts
    -- Remove the unique constraint on employee_id to allow history/multiple contracts (if applicable)
    DROP CONSTRAINT IF EXISTS contracts_employee_id_key;

ALTER TABLE public.contracts
    -- Status info
    ADD COLUMN IF NOT EXISTS internal_contract_number VARCHAR(100),
    ADD COLUMN IF NOT EXISTS contract_language VARCHAR(50) DEFAULT 'Arabic/English',
    ADD COLUMN IF NOT EXISTS qiwa_reference_number VARCHAR(100),
    ADD COLUMN IF NOT EXISTS previous_contract_id UUID REFERENCES public.contracts(id),

    -- Employer Snapshot
    ADD COLUMN IF NOT EXISTS employer_name_ar VARCHAR(255),
    ADD COLUMN IF NOT EXISTS employer_name_en VARCHAR(255),
    ADD COLUMN IF NOT EXISTS commercial_registration VARCHAR(50),
    ADD COLUMN IF NOT EXISTS unified_establishment_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS employer_address TEXT,
    ADD COLUMN IF NOT EXISTS employer_city VARCHAR(100),
    ADD COLUMN IF NOT EXISTS employer_region VARCHAR(100),
    ADD COLUMN IF NOT EXISTS authorized_rep_name VARCHAR(255),
    ADD COLUMN IF NOT EXISTS authorized_rep_title VARCHAR(255),

    -- Employee Snapshot
    ADD COLUMN IF NOT EXISTS employee_number VARCHAR(100),
    ADD COLUMN IF NOT EXISTS employee_name_ar VARCHAR(255),
    ADD COLUMN IF NOT EXISTS employee_name_en VARCHAR(255),
    ADD COLUMN IF NOT EXISTS nationality VARCHAR(100),
    ADD COLUMN IF NOT EXISTS is_saudi BOOLEAN DEFAULT true,
    ADD COLUMN IF NOT EXISTS identity_document_type VARCHAR(100),
    ADD COLUMN IF NOT EXISTS identity_number VARCHAR(100),
    ADD COLUMN IF NOT EXISTS identity_expiry_date DATE,
    ADD COLUMN IF NOT EXISTS date_of_birth DATE,
    ADD COLUMN IF NOT EXISTS employee_address TEXT,
    ADD COLUMN IF NOT EXISTS employee_city VARCHAR(100),
    ADD COLUMN IF NOT EXISTS employee_region VARCHAR(100),
    ADD COLUMN IF NOT EXISTS employee_mobile VARCHAR(50),
    ADD COLUMN IF NOT EXISTS employee_email VARCHAR(255),

    -- Job Info
    ADD COLUMN IF NOT EXISTS profession VARCHAR(255),
    ADD COLUMN IF NOT EXISTS job_title_ar VARCHAR(255),
    ADD COLUMN IF NOT EXISTS job_title_en VARCHAR(255),
    ADD COLUMN IF NOT EXISTS department VARCHAR(255),
    ADD COLUMN IF NOT EXISTS reporting_manager VARCHAR(255),
    ADD COLUMN IF NOT EXISTS work_type VARCHAR(100),
    ADD COLUMN IF NOT EXISTS primary_workplace VARCHAR(255),
    ADD COLUMN IF NOT EXISTS work_city VARCHAR(100),
    ADD COLUMN IF NOT EXISTS work_region VARCHAR(100),
    ADD COLUMN IF NOT EXISTS work_arrangement VARCHAR(100),
    ADD COLUMN IF NOT EXISTS employment_commencement_date DATE,

    -- Contract Type & Duration
    ADD COLUMN IF NOT EXISTS contract_duration_desc VARCHAR(255),
    ADD COLUMN IF NOT EXISTS renewal_option VARCHAR(255),
    ADD COLUMN IF NOT EXISTS project_description TEXT,

    -- Probation Period
    ADD COLUMN IF NOT EXISTS probation_enabled BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS probation_end_date DATE,
    ADD COLUMN IF NOT EXISTS probation_terms TEXT,

    -- Compensation
    ADD COLUMN IF NOT EXISTS basic_monthly_wage DECIMAL(10, 2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS commission_details TEXT,
    ADD COLUMN IF NOT EXISTS bonus_details TEXT,
    ADD COLUMN IF NOT EXISTS in_kind_benefits TEXT,
    ADD COLUMN IF NOT EXISTS wage_payment_frequency VARCHAR(100) DEFAULT 'Monthly',
    ADD COLUMN IF NOT EXISTS wage_payment_schedule VARCHAR(255),
    ADD COLUMN IF NOT EXISTS payment_method VARCHAR(100) DEFAULT 'Bank Transfer',
    ADD COLUMN IF NOT EXISTS bank_name VARCHAR(255),
    ADD COLUMN IF NOT EXISTS iban VARCHAR(100),
    ADD COLUMN IF NOT EXISTS overtime_treatment VARCHAR(255),
    ADD COLUMN IF NOT EXISTS financial_deductions TEXT,
    ADD COLUMN IF NOT EXISTS additional_financial_obligations TEXT,

    -- Working Time and Rest
    ADD COLUMN IF NOT EXISTS working_days_per_week INTEGER DEFAULT 5,
    ADD COLUMN IF NOT EXISTS daily_working_hours INTEGER DEFAULT 8,
    ADD COLUMN IF NOT EXISTS weekly_working_hours INTEGER DEFAULT 40,
    ADD COLUMN IF NOT EXISTS shift_type VARCHAR(100),
    ADD COLUMN IF NOT EXISTS daily_rest_arrangements TEXT,
    ADD COLUMN IF NOT EXISTS weekly_rest_day VARCHAR(100) DEFAULT 'Friday, Saturday',
    ADD COLUMN IF NOT EXISTS ramadan_schedule_applicability BOOLEAN DEFAULT true,

    -- Leave & Benefits
    ADD COLUMN IF NOT EXISTS official_holidays TEXT,
    ADD COLUMN IF NOT EXISTS sick_leave_reference TEXT,
    ADD COLUMN IF NOT EXISTS other_leaves_reference TEXT,
    ADD COLUMN IF NOT EXISTS medical_insurance_details TEXT,
    ADD COLUMN IF NOT EXISTS social_insurance_applicability BOOLEAN DEFAULT true,
    ADD COLUMN IF NOT EXISTS housing_benefit TEXT,
    ADD COLUMN IF NOT EXISTS transportation_benefit TEXT,

    -- Rights, obligations, and clauses
    ADD COLUMN IF NOT EXISTS employee_duties TEXT,
    ADD COLUMN IF NOT EXISTS employer_obligations TEXT,
    ADD COLUMN IF NOT EXISTS confidentiality_clause TEXT,
    ADD COLUMN IF NOT EXISTS intellectual_property_clause TEXT,
    ADD COLUMN IF NOT EXISTS data_protection_clause TEXT,
    ADD COLUMN IF NOT EXISTS health_safety_clause TEXT,
    ADD COLUMN IF NOT EXISTS transfer_relocation_clause TEXT,
    ADD COLUMN IF NOT EXISTS training_obligations TEXT,
    ADD COLUMN IF NOT EXISTS non_compete_clause TEXT,
    ADD COLUMN IF NOT EXISTS termination_clause TEXT,
    ADD COLUMN IF NOT EXISTS end_of_service_benefits_clause TEXT,
    ADD COLUMN IF NOT EXISTS dispute_resolution TEXT,
    ADD COLUMN IF NOT EXISTS governing_law VARCHAR(255) DEFAULT 'Saudi Labor Law',
    ADD COLUMN IF NOT EXISTS additional_clauses TEXT;

ALTER TABLE public.contracts DROP CONSTRAINT IF EXISTS contracts_status_check;
ALTER TABLE public.contracts ADD CONSTRAINT contracts_status_check 
    CHECK (status IN ('Draft', 'Pending Review', 'Pending Employee Approval', 'Active', 'Rejected', 'Expired', 'Terminated', 'Cancelled'));

ALTER TABLE public.contracts ALTER COLUMN start_date DROP NOT NULL;

-- Enable RLS for settings tables
ALTER TABLE public.establishment_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contract_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Policies for establishment_settings
DROP POLICY IF EXISTS "Everyone can view establishment settings" ON public.establishment_settings;
DROP POLICY IF EXISTS "Admins can edit establishment settings" ON public.establishment_settings;
CREATE POLICY "Everyone can view establishment settings" ON public.establishment_settings FOR SELECT USING (true);
CREATE POLICY "Admins can edit establishment settings" ON public.establishment_settings FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- Policies for contract_settings
DROP POLICY IF EXISTS "Everyone can view contract settings" ON public.contract_settings;
DROP POLICY IF EXISTS "Admins can edit contract settings" ON public.contract_settings;
CREATE POLICY "Everyone can view contract settings" ON public.contract_settings FOR SELECT USING (true);
CREATE POLICY "Admins can edit contract settings" ON public.contract_settings FOR ALL USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));

-- Policies for audit_logs
DROP POLICY IF EXISTS "Admins can view audit logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Admins can insert audit logs" ON public.audit_logs;
CREATE POLICY "Admins can view audit logs" ON public.audit_logs FOR SELECT USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));
CREATE POLICY "Admins can insert audit logs" ON public.audit_logs FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'ADMIN'));
