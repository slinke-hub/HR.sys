-- Clear dashboard recent-login history without removing users or profiles.
UPDATE public.profiles
SET last_login = NULL;
