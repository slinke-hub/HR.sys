-- Extend the existing admin access model to control page visibility and
-- named application features without changing business data or workflows.
BEGIN;

ALTER TABLE public.role_permissions
  ADD COLUMN IF NOT EXISTS disabled_features JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.role_permissions
  ADD COLUMN IF NOT EXISTS disabled_pages JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.user_permissions
  ADD COLUMN IF NOT EXISTS disabled_features JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.user_permissions
  ADD COLUMN IF NOT EXISTS disabled_pages JSONB NOT NULL DEFAULT '[]'::jsonb;

DROP POLICY IF EXISTS "Allow admins to modify role permissions" ON public.role_permissions;
CREATE POLICY "Allow admins to modify role permissions"
  ON public.role_permissions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profiles.role, ''), '[_-]+', ' ', 'g'))) IN
          ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'SYSTEM ADMINISTRATOR')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profiles.role, ''), '[_-]+', ' ', 'g'))) IN
          ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'SYSTEM ADMINISTRATOR')
    )
  );

DROP POLICY IF EXISTS "Allow authenticated users to read their own permissions" ON public.user_permissions;
CREATE POLICY "Allow authenticated users to read their own permissions"
  ON public.user_permissions
  FOR SELECT
  USING (
    auth.uid() = user_id OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profiles.role, ''), '[_-]+', ' ', 'g'))) IN
          ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'SYSTEM ADMINISTRATOR')
    )
  );

DROP POLICY IF EXISTS "Allow admins to modify user permissions" ON public.user_permissions;
CREATE POLICY "Allow admins to modify user permissions"
  ON public.user_permissions
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profiles.role, ''), '[_-]+', ' ', 'g'))) IN
          ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'SYSTEM ADMINISTRATOR')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid()
        AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profiles.role, ''), '[_-]+', ' ', 'g'))) IN
          ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'SYSTEM ADMINISTRATOR')
    )
  );

COMMIT;
