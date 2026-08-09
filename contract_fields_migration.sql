-- Add new fields to the contracts table
ALTER TABLE public.contracts
ADD COLUMN IF NOT EXISTS housing_allowance DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS transportation_allowance DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS other_allowances DECIMAL(10, 2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS working_hours VARCHAR(50) DEFAULT '8 hours/day',
ADD COLUMN IF NOT EXISTS probation_period_days INTEGER DEFAULT 90,
ADD COLUMN IF NOT EXISTS notice_period_days INTEGER DEFAULT 30,
ADD COLUMN IF NOT EXISTS annual_leave_days INTEGER DEFAULT 30;
