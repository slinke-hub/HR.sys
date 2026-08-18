-- Run this in your Supabase SQL Editor to set the user as ADMIN
UPDATE public.profiles
SET role = 'ADMIN'
WHERE id = (SELECT id FROM auth.users WHERE email = 'privatepple@gmail.com');
