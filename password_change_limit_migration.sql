-- Migration to add password changes count to track the 3-limit restriction
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS password_changes_count INT NOT NULL DEFAULT 0;

-- Optional: Reset any existing counts
-- UPDATE public.profiles SET password_changes_count = 0;
