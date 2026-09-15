BEGIN;

-- Central authorization rule for CRM and project financial information.
CREATE OR REPLACE FUNCTION public.can_view_business_financials(
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        LEFT JOIN public.departments department ON department.id = profile.department_id
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM FALSE
          AND (
              profile.emp_index IN (4, 5)
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER',
                  'GM', 'GENERAL MANAGER', 'MARKETING MANAGER'
              )
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) ~
                 '(^| )(CEO|CHIEF EXECUTIVE|CHIEF EXECUTIVE OFFICER|GM|GENERAL MANAGER|MARKETING MANAGER)( |$)'
              OR COALESCE(profile.job_title_ar, '') ~ '(الرئيس التنفيذي|المدير العام|مدير.*التسويق|التسويق.*مدير)'
              OR (COALESCE(department.name, '') || ' ' || COALESCE(department.name_ar, '')) ~* '(sales|المبيعات)'
              OR (
                  (COALESCE(department.name, '') || ' ' || COALESCE(department.name_ar, '')) ~* '(marketing|التسويق)'
                  AND (
                      profile.id = department.head_id
                      OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) = 'MANAGER'
                      OR UPPER(COALESCE(profile.job_title, '')) ~ 'MARKETING[^A-Z]*MANAGER|MANAGER[^A-Z]*MARKETING'
                      OR COALESCE(profile.job_title_ar, '') ~ '(مدير.*التسويق|التسويق.*مدير)'
                  )
              )
          )
    );
$$;

-- Return the normal CRM deal record, but redact the amount before it reaches
-- clients that do not have financial access.
CREATE OR REPLACE FUNCTION public.list_crm_deals_secure()
RETURNS SETOF JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT
        to_jsonb(deal)
        || jsonb_build_object(
            'amount', CASE
                WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(deal.amount)
                ELSE 'null'::JSONB
            END,
            'crm_clients', CASE WHEN client.id IS NULL THEN NULL ELSE to_jsonb(client) END
        )
    FROM public.crm_deals deal
    LEFT JOIN public.crm_clients client ON client.id = deal.client_id
    WHERE auth.uid() IS NOT NULL
      AND public.can_access_crm(auth.uid())
    ORDER BY deal.created_at DESC;
$$;

-- Apply the same redaction to project budgets, costs, project value, and paid
-- amount. payment_ready lets the existing completion gate work without
-- revealing either underlying amount.
CREATE OR REPLACE FUNCTION public.list_accessible_projects_secure()
RETURNS SETOF JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT
        to_jsonb(project)
        || jsonb_build_object(
            'project_amount', CASE
                WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(project.project_amount)
                ELSE 'null'::JSONB
            END,
            'paid_amount', CASE
                WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(project.paid_amount)
                ELSE 'null'::JSONB
            END,
            'budget_amount', CASE
                WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(project.budget_amount)
                ELSE 'null'::JSONB
            END,
            'actual_cost', CASE
                WHEN public.can_view_business_financials(auth.uid()) THEN to_jsonb(project.actual_cost)
                ELSE 'null'::JSONB
            END,
            'payment_ready', COALESCE(project.project_amount, 0) <= 0
                OR COALESCE(project.paid_amount, 0) >= COALESCE(project.project_amount, 0),
            'crm_clients', CASE WHEN client.id IS NULL THEN NULL ELSE jsonb_build_object('name', client.name, 'company', client.company) END
        )
    FROM public.projects project
    LEFT JOIN public.crm_clients client ON client.id = project.client_id
    WHERE auth.uid() IS NOT NULL
      AND public.can_access_project(project.id, auth.uid())
    ORDER BY project.created_at DESC;
$$;

-- Remove direct reads of the sensitive columns. Authorized users receive
-- them through the secure functions above; other project/deal columns remain
-- available for the existing RLS-protected workflows.
REVOKE SELECT ON TABLE public.crm_deals FROM authenticated;
REVOKE SELECT ON TABLE public.projects FROM authenticated;

DO $$
DECLARE
    selectable_columns TEXT;
BEGIN
    SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
      INTO selectable_columns
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'crm_deals'
       AND column_name <> 'amount';
    EXECUTE 'GRANT SELECT (' || selectable_columns || ') ON TABLE public.crm_deals TO authenticated';

    SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
      INTO selectable_columns
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'projects'
       AND column_name NOT IN ('project_amount', 'paid_amount', 'budget_amount', 'actual_cost');
    EXECUTE 'GRANT SELECT (' || selectable_columns || ') ON TABLE public.projects TO authenticated';
END;
$$;

REVOKE ALL ON FUNCTION public.can_view_business_financials(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_crm_deals_secure() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_accessible_projects_secure() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_business_financials(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_crm_deals_secure() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_accessible_projects_secure() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
