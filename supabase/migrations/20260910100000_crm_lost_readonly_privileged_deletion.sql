-- Keep lost CRM deals read-only and restrict permanent deletion to leadership.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_delete_crm_deal(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM false
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'CEO', 'GM', 'GENERAL MANAGER'
              )
              OR UPPER(COALESCE(profile.job_title, '')) ~ '(^|[^A-Z])(CEO|CHIEF EXECUTIVE|CHIEF EXECUTIVE OFFICER|GM|GENERAL MANAGER|MARKETING MANAGER)([^A-Z]|$)'
              OR COALESCE(to_jsonb(profile)->>'job_title_ar', '') ~ '(الرئيس التنفيذي|المدير العام|مدير[[:space:]]*التسويق)'
          )
    );
$$;

REVOKE ALL ON FUNCTION public.can_delete_crm_deal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_delete_crm_deal(uuid) TO authenticated;

-- Replace broad legacy policies so DELETE is no longer available to every CRM user.
DROP POLICY IF EXISTS "Users can view deals" ON public.crm_deals;
DROP POLICY IF EXISTS "Users can insert deals" ON public.crm_deals;
DROP POLICY IF EXISTS "Users can update deals" ON public.crm_deals;
DROP POLICY IF EXISTS "Users can delete deals" ON public.crm_deals;
DROP POLICY IF EXISTS crm_authorized_deals_all ON public.crm_deals;
DROP POLICY IF EXISTS crm_authorized_deals_select ON public.crm_deals;
DROP POLICY IF EXISTS crm_authorized_deals_insert ON public.crm_deals;
DROP POLICY IF EXISTS crm_authorized_deals_update ON public.crm_deals;
DROP POLICY IF EXISTS crm_privileged_deals_delete ON public.crm_deals;

CREATE POLICY crm_authorized_deals_select ON public.crm_deals
FOR SELECT TO authenticated
USING (public.can_access_crm(auth.uid()));

CREATE POLICY crm_authorized_deals_insert ON public.crm_deals
FOR INSERT TO authenticated
WITH CHECK (public.can_access_crm(auth.uid()));

CREATE POLICY crm_authorized_deals_update ON public.crm_deals
FOR UPDATE TO authenticated
USING (public.can_access_crm(auth.uid()))
WITH CHECK (public.can_access_crm(auth.uid()));

CREATE POLICY crm_privileged_deals_delete ON public.crm_deals
FOR DELETE TO authenticated
USING (public.can_delete_crm_deal(auth.uid()));

CREATE OR REPLACE FUNCTION public.protect_lost_crm_deal_edits()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF UPPER(COALESCE(OLD.stage, '')) = 'LOST'
       AND UPPER(COALESCE(NEW.stage, '')) = 'LOST'
       AND (to_jsonb(NEW) - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'updated_at') THEN
        RAISE EXCEPTION 'Lost deals are read-only until moved to another stage'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_lost_crm_deal_edits_trigger ON public.crm_deals;
CREATE TRIGGER protect_lost_crm_deal_edits_trigger
BEFORE UPDATE ON public.crm_deals
FOR EACH ROW
EXECUTE FUNCTION public.protect_lost_crm_deal_edits();

CREATE OR REPLACE FUNCTION public.delete_crm_deal(p_deal_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    deleted_id uuid;
BEGIN
    IF NOT public.can_delete_crm_deal(auth.uid()) THEN
        RAISE EXCEPTION 'Only Admin, CEO, GM, or Marketing Manager may delete CRM deals'
            USING ERRCODE = '42501';
    END IF;

    DELETE FROM public.crm_deals
    WHERE id = p_deal_id
    RETURNING id INTO deleted_id;

    IF deleted_id IS NULL THEN
        RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002';
    END IF;
    RETURN deleted_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_crm_deal(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_crm_deal(uuid) TO authenticated;

DROP POLICY IF EXISTS crm_deal_files_privileged_delete ON storage.objects;
CREATE POLICY crm_deal_files_privileged_delete ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'crm-deal-files' AND public.can_delete_crm_deal(auth.uid()));

NOTIFY pgrst, 'reload schema';
COMMIT;
