BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
DECLARE
  expected record;
  policy_count integer;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'CRM read-policy hardening requires the postgres migration owner';
  END IF;

  IF NOT has_schema_privilege('authenticated', 'public', 'USAGE') THEN
    RAISE EXCEPTION 'Authenticated users lack the existing public schema USAGE privilege';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('crm_deal_activity'),
      ('crm_deal_approval_steps'),
      ('crm_deal_attachments')
    ) AS target(table_name)
    LEFT JOIN pg_class AS relation
      ON relation.relnamespace = 'public'::regnamespace
     AND relation.relname = target.table_name
    WHERE relation.oid IS NULL OR NOT relation.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'A target CRM relation is missing or no longer has RLS enabled';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('crm_deal_activity'),
      ('crm_deal_approval_steps'),
      ('crm_deal_attachments')
    ) AS target(table_name)
    WHERE NOT has_table_privilege('authenticated', format('public.%I', target.table_name), 'SELECT')
  ) THEN
    RAISE EXCEPTION 'Authenticated CRM SELECT privilege differs from the reviewed baseline';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('crm_deal_activity', 4),
      ('crm_deal_approval_steps', 2),
      ('crm_deal_attachments', 7)
    ) AS policy_baseline(table_name, policy_count)
    WHERE (SELECT count(*) FROM pg_policies AS policy
           WHERE policy.schemaname = 'public'
             AND policy.tablename = policy_baseline.table_name) <> policy_baseline.policy_count
  ) THEN
    RAISE EXCEPTION 'CRM policy inventory differs from the reviewed Production baseline';
  END IF;

  FOR expected IN
    SELECT * FROM (VALUES
      ('crm_deal_activity', 'Authenticated users can view deal activity', 'b326b5062b2f0e69046810717534cb09'),
      ('crm_deal_approval_steps', 'Authenticated users can view deal approvals', 'b326b5062b2f0e69046810717534cb09'),
      ('crm_deal_attachments', 'Authenticated users can view deal attachments', 'b326b5062b2f0e69046810717534cb09')
    ) AS policies(table_name, policy_name, qual_md5)
  LOOP
    SELECT count(*)
      INTO policy_count
      FROM pg_policies AS policy
     WHERE policy.schemaname = 'public'
       AND policy.tablename = expected.table_name
       AND policy.policyname = expected.policy_name
       AND policy.permissive = 'PERMISSIVE'
       AND policy.roles = ARRAY['authenticated']::name[]
       AND policy.cmd = 'SELECT'
       AND policy.qual IS NOT NULL
       AND md5(policy.qual) = expected.qual_md5
       AND policy.with_check IS NULL;

    IF policy_count <> 1 THEN
      RAISE EXCEPTION 'Expected broad legacy CRM read policy is absent or has drifted: %.%',
        expected.table_name, expected.policy_name;
    END IF;
  END LOOP;

  -- Reject a newly-added permissive blanket reader instead of silently
  -- leaving it in place beside the reviewed scoped policies.
  IF EXISTS (
    SELECT 1
    FROM pg_policies AS policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename IN ('crm_deal_activity', 'crm_deal_approval_steps', 'crm_deal_attachments')
      AND policy.permissive = 'PERMISSIVE'
      AND policy.cmd IN ('ALL', 'SELECT')
      AND policy.qual IN ('true', '(true)')
      AND policy.policyname NOT IN (
        'Authenticated users can view deal activity',
        'Authenticated users can view deal approvals',
        'Authenticated users can view deal attachments'
      )
  ) THEN
    RAISE EXCEPTION 'An unreviewed permissive blanket CRM read policy exists';
  END IF;

  -- Require the intended authorized replacements and exact expressions before
  -- removing the broad policies. Their MD5 values come from the reviewed live
  -- Production catalog export.
  FOR expected IN
    SELECT * FROM (VALUES
      ('crm_deal_activity', 'crm_authorized_activity_select', 'eb8c3613925a4ec015c5b577a9f8f737'),
      ('crm_deal_approval_steps', 'crm_authorized_approval_steps_select', 'eb8c3613925a4ec015c5b577a9f8f737'),
      ('crm_deal_attachments', 'crm_authorized_attachments_select', '62764aebd28b1ac38c5f3b11558e7bf2'),
      ('crm_deal_attachments', 'crm_project_shared_attachments_select', 'd365bd9a306d4684348c68de08c83cc3')
    ) AS policies(table_name, policy_name, qual_md5)
  LOOP
    SELECT count(*)
      INTO policy_count
      FROM pg_policies AS policy
     WHERE policy.schemaname = 'public'
       AND policy.tablename = expected.table_name
       AND policy.policyname = expected.policy_name
       AND policy.permissive = 'PERMISSIVE'
       AND policy.roles = ARRAY['authenticated']::name[]
       AND policy.cmd = 'SELECT'
       AND policy.qual IS NOT NULL
       AND md5(policy.qual) = expected.qual_md5
       AND policy.with_check IS NULL;

    IF policy_count <> 1 THEN
      RAISE EXCEPTION 'Required scoped CRM read policy is absent or has drifted: %.%',
        expected.table_name, expected.policy_name;
    END IF;
  END LOOP;

  -- Anonymous approval reads and all direct approval writes must remain
  -- denied by RLS even though table privileges exist.
  IF EXISTS (
    SELECT 1
    FROM pg_policies AS policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = 'crm_deal_approval_steps'
      AND policy.cmd IN ('ALL', 'SELECT')
      AND (policy.roles && ARRAY['anon', 'public']::name[])
  ) THEN
    RAISE EXCEPTION 'An anonymous or PUBLIC approval-step read policy exists';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_policies AS policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = 'crm_deal_approval_steps'
      AND policy.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
      AND (policy.roles && ARRAY['anon', 'authenticated', 'public']::name[])
  ) THEN
    RAISE EXCEPTION 'An unexpected direct approval-step write policy exists';
  END IF;
END
$preflight$;

DROP POLICY "Authenticated users can view deal activity" ON public.crm_deal_activity;
DROP POLICY "Authenticated users can view deal approvals" ON public.crm_deal_approval_steps;
DROP POLICY "Authenticated users can view deal attachments" ON public.crm_deal_attachments;

DO $postcheck$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND policyname IN (
        'Authenticated users can view deal activity',
        'Authenticated users can view deal approvals',
        'Authenticated users can view deal attachments'
      )
  ) THEN
    RAISE EXCEPTION 'A removed blanket CRM read policy remains';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('crm_deal_activity'),
      ('crm_deal_approval_steps'),
      ('crm_deal_attachments')
    ) AS target(table_name)
    LEFT JOIN pg_class AS relation
      ON relation.relnamespace = 'public'::regnamespace
     AND relation.relname = target.table_name
    WHERE relation.oid IS NULL OR NOT relation.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'CRM RLS was not preserved';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('crm_deal_activity', 3),
      ('crm_deal_approval_steps', 1),
      ('crm_deal_attachments', 6)
    ) AS policy_baseline(table_name, policy_count)
    WHERE (SELECT count(*) FROM pg_policies AS policy
           WHERE policy.schemaname = 'public'
             AND policy.tablename = policy_baseline.table_name) <> policy_baseline.policy_count
  ) THEN
    RAISE EXCEPTION 'Unexpected CRM policy changes occurred during hardening';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('crm_deal_activity', 'crm_authorized_activity_select', 'eb8c3613925a4ec015c5b577a9f8f737'),
      ('crm_deal_approval_steps', 'crm_authorized_approval_steps_select', 'eb8c3613925a4ec015c5b577a9f8f737'),
      ('crm_deal_attachments', 'crm_authorized_attachments_select', '62764aebd28b1ac38c5f3b11558e7bf2'),
      ('crm_deal_attachments', 'crm_project_shared_attachments_select', 'd365bd9a306d4684348c68de08c83cc3')
    ) AS expected(table_name, policy_name, qual_md5)
    WHERE NOT EXISTS (
      SELECT 1
      FROM pg_policies AS policy
      WHERE policy.schemaname = 'public'
        AND policy.tablename = expected.table_name
        AND policy.policyname = expected.policy_name
        AND policy.permissive = 'PERMISSIVE'
        AND policy.roles = ARRAY['authenticated']::name[]
        AND policy.cmd = 'SELECT'
        AND policy.qual IS NOT NULL
        AND md5(policy.qual) = expected.qual_md5
        AND policy.with_check IS NULL
    )
  ) THEN
    RAISE EXCEPTION 'A scoped CRM read policy changed during hardening';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_policies AS policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = 'crm_deal_approval_steps'
      AND policy.cmd IN ('ALL', 'SELECT')
      AND (policy.roles && ARRAY['anon', 'public']::name[])
  ) THEN
    RAISE EXCEPTION 'Anonymous approval reads are no longer denied by RLS';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_policies AS policy
    WHERE policy.schemaname = 'public'
      AND policy.tablename = 'crm_deal_approval_steps'
      AND policy.cmd IN ('ALL', 'INSERT', 'UPDATE', 'DELETE')
      AND (policy.roles && ARRAY['anon', 'authenticated', 'public']::name[])
  ) THEN
    RAISE EXCEPTION 'Direct approval writes are no longer denied by RLS';
  END IF;
END
$postcheck$;

COMMIT;
