-- Read-only staging catalog guard used by the authenticated Phase 1 harness.
WITH checks AS (
  SELECT
    NOT has_table_privilege('authenticated','public.projects','SELECT')
      AND NOT has_table_privilege('authenticated','public.projects','INSERT')
      AND NOT has_table_privilege('authenticated','public.projects','UPDATE')
      AND NOT has_table_privilege('authenticated','public.projects','DELETE') AS direct_project_table_access_denied,
    to_regprocedure('public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)') IS NOT NULL
      AND NOT has_function_privilege('authenticated','public.create_project_from_won_deal(uuid,date,date,date,date,text,numeric,numeric,text,text)','EXECUTE') AS legacy_deal_conversion_revoked,
    EXISTS (
      SELECT 1 FROM pg_class relation
      JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
      WHERE namespace.nspname='public' AND relation.relname='projects' AND relation.relrowsecurity
    ) AS project_rls_enabled
)
SELECT 'PHASE1SECURITY|' || CASE WHEN direct_project_table_access_denied AND legacy_deal_conversion_revoked AND project_rls_enabled THEN 'PASS' ELSE 'FAIL' END
  || '|direct_table=' || direct_project_table_access_denied
  || ';legacy_deal_rpc_revoked=' || legacy_deal_conversion_revoked
  || ';rls_enabled=' || project_rls_enabled AS verification_marker
FROM checks;
