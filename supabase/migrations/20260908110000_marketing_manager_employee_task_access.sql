-- Marketing task-list management and employee-to-employee read-only task access.
BEGIN;

CREATE TABLE IF NOT EXISTS public.task_employee_access_grants (
    viewer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    subject_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    granted_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (viewer_id, subject_id),
    CONSTRAINT task_employee_access_different_people CHECK (viewer_id <> subject_id)
);

ALTER TABLE public.task_employee_access_grants ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.task_employee_access_grants TO authenticated;

CREATE OR REPLACE FUNCTION public.is_marketing_task_manager(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        LEFT JOIN public.departments department ON department.id = profile.department_id
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM false
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) LIKE '%MARKETING MANAGER%'
              OR COALESCE(profile.job_title, '') ~* 'مدير[[:space:]]*التسويق'
              OR (
                  (COALESCE(department.name, '') || ' ' || COALESCE(department.name_ar, '')) ~* '(marketing|التسويق)'
                  AND p_user_id = department.head_id
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.is_sales_marketing_employee(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        JOIN public.departments department ON department.id = profile.department_id
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM false
          AND (COALESCE(department.name, '') || ' ' || COALESCE(department.name_ar, '')) ~* '(sales|marketing|المبيعات|التسويق)'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_marketing_managed_task_list(p_list_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.task_lists list
        WHERE list.id = p_list_id
          AND COALESCE(list.name, '') ~* '(design|marketing|sales|تصميم|تسويق|مبيعات)'
    );
$$;

CREATE OR REPLACE FUNCTION public.task_belongs_to_employee(p_task_id uuid, p_employee_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tasks task
        WHERE task.id = p_task_id
          AND (
              task.created_by = p_employee_id
              OR task.assignee_id = p_employee_id
              OR p_employee_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_task_via_employee_grant(
    p_task_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.task_employee_access_grants access
        JOIN public.tasks task ON task.id = p_task_id
        WHERE access.viewer_id = p_user_id
          AND (
              task.created_by = access.subject_id
              OR task.assignee_id = access.subject_id
              OR access.subject_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_task_list_via_employee_grant(
    p_list_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tasks task
        JOIN public.task_employee_access_grants access
          ON access.viewer_id = p_user_id
         AND (
              task.created_by = access.subject_id
              OR task.assignee_id = access.subject_id
              OR access.subject_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
         )
        WHERE task.task_list_id = p_list_id
    );
$$;

CREATE OR REPLACE FUNCTION public.can_marketing_manager_edit_task(
    p_task_id uuid,
    p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT public.is_marketing_task_manager(p_user_id)
       AND EXISTS (
           SELECT 1
           FROM public.tasks task
           WHERE task.id = p_task_id
             AND public.is_marketing_managed_task_list(task.task_list_id)
       );
$$;

CREATE OR REPLACE FUNCTION public.is_mq20_profile(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND UPPER(BTRIM(COALESCE(profile.employee_id, ''))) = 'MQ-20'
          AND profile.is_active IS DISTINCT FROM false
    );
$$;

CREATE OR REPLACE FUNCTION public.is_ines_modani_profile(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM false
          AND (
              UPPER(BTRIM(COALESCE(profile.employee_id, ''))) = 'MQ-08'
              OR (COALESCE(profile.full_name, '') || ' ' || COALESCE(profile.display_name, '')) ~* '((ines|enas).*(modani|madani)|(modani|madani).*(ines|enas))'
              OR COALESCE(profile.display_name_ar, '') ~* '(ايناس|إيناس).*مدني'
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.is_ines_modani_task(p_task_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tasks task
        JOIN public.profiles ines
          ON public.is_ines_modani_profile(ines.id)
         AND (
              task.created_by = ines.id
              OR task.assignee_id = ines.id
              OR ines.id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
         )
        WHERE task.id = p_task_id
    );
$$;

CREATE OR REPLACE FUNCTION public.is_ines_modani_task_list(p_list_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tasks task
        WHERE task.task_list_id = p_list_id
          AND public.is_ines_modani_task(task.id)
    );
$$;

DROP POLICY IF EXISTS task_employee_access_visible ON public.task_employee_access_grants;
CREATE POLICY task_employee_access_visible ON public.task_employee_access_grants
FOR SELECT TO authenticated
USING (viewer_id = auth.uid() OR public.is_marketing_task_manager(auth.uid()));

DROP POLICY IF EXISTS marketing_and_granted_tasks_select ON public.tasks;
CREATE POLICY marketing_and_granted_tasks_select ON public.tasks
FOR SELECT TO authenticated
USING (
    public.can_view_task_via_employee_grant(id, auth.uid())
    OR public.can_marketing_manager_edit_task(id, auth.uid())
);

DROP POLICY IF EXISTS marketing_manager_tasks_update ON public.tasks;
CREATE POLICY marketing_manager_tasks_update ON public.tasks
FOR UPDATE TO authenticated
USING (public.can_marketing_manager_edit_task(id, auth.uid()))
WITH CHECK (
    public.is_marketing_task_manager(auth.uid())
    AND public.is_marketing_managed_task_list(task_list_id)
);

DROP POLICY IF EXISTS marketing_and_granted_task_lists_select ON public.task_lists;
CREATE POLICY marketing_and_granted_task_lists_select ON public.task_lists
FOR SELECT TO authenticated
USING (
    (public.is_marketing_task_manager(auth.uid()) AND public.is_marketing_managed_task_list(id))
    OR public.can_view_task_list_via_employee_grant(id, auth.uid())
);

-- MQ-20 is a view-only observer and must only receive Ines Modani task rows.
DROP POLICY IF EXISTS mq20_only_ines_tasks_select ON public.tasks;
CREATE POLICY mq20_only_ines_tasks_select ON public.tasks AS RESTRICTIVE
FOR SELECT TO authenticated
USING (NOT public.is_mq20_profile(auth.uid()) OR public.is_ines_modani_task(id));

DROP POLICY IF EXISTS mq20_no_tasks_insert ON public.tasks;
CREATE POLICY mq20_no_tasks_insert ON public.tasks AS RESTRICTIVE
FOR INSERT TO authenticated
WITH CHECK (NOT public.is_mq20_profile(auth.uid()));

DROP POLICY IF EXISTS mq20_no_tasks_update ON public.tasks;
CREATE POLICY mq20_no_tasks_update ON public.tasks AS RESTRICTIVE
FOR UPDATE TO authenticated
USING (NOT public.is_mq20_profile(auth.uid()))
WITH CHECK (NOT public.is_mq20_profile(auth.uid()));

DROP POLICY IF EXISTS mq20_no_tasks_delete ON public.tasks;
CREATE POLICY mq20_no_tasks_delete ON public.tasks AS RESTRICTIVE
FOR DELETE TO authenticated
USING (NOT public.is_mq20_profile(auth.uid()));

DROP POLICY IF EXISTS mq20_only_ines_task_lists_select ON public.task_lists;
CREATE POLICY mq20_only_ines_task_lists_select ON public.task_lists AS RESTRICTIVE
FOR SELECT TO authenticated
USING (NOT public.is_mq20_profile(auth.uid()) OR public.is_ines_modani_task_list(id));

DROP POLICY IF EXISTS mq20_no_task_lists_insert ON public.task_lists;
CREATE POLICY mq20_no_task_lists_insert ON public.task_lists AS RESTRICTIVE
FOR INSERT TO authenticated
WITH CHECK (NOT public.is_mq20_profile(auth.uid()));

DROP POLICY IF EXISTS mq20_no_task_lists_update ON public.task_lists;
CREATE POLICY mq20_no_task_lists_update ON public.task_lists AS RESTRICTIVE
FOR UPDATE TO authenticated
USING (NOT public.is_mq20_profile(auth.uid()))
WITH CHECK (NOT public.is_mq20_profile(auth.uid()));

DROP POLICY IF EXISTS mq20_no_task_lists_delete ON public.task_lists;
CREATE POLICY mq20_no_task_lists_delete ON public.task_lists AS RESTRICTIVE
FOR DELETE TO authenticated
USING (NOT public.is_mq20_profile(auth.uid()));

-- Keep the observer role read-only across task child records as well. These
-- tables are optional in older installations, so create the policies only
-- when each table is present.
DO $$
BEGIN
    IF to_regclass('public.task_comments') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS marketing_and_granted_task_comments_select ON public.task_comments';
        EXECUTE 'CREATE POLICY marketing_and_granted_task_comments_select ON public.task_comments FOR SELECT TO authenticated USING (public.can_view_task_via_employee_grant(task_id, auth.uid()) OR public.can_marketing_manager_edit_task(task_id, auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS mq20_only_ines_task_comments_select ON public.task_comments';
        EXECUTE 'CREATE POLICY mq20_only_ines_task_comments_select ON public.task_comments AS RESTRICTIVE FOR SELECT TO authenticated USING (NOT public.is_mq20_profile(auth.uid()) OR public.is_ines_modani_task(task_id))';
        EXECUTE 'DROP POLICY IF EXISTS marketing_manager_task_comments_insert ON public.task_comments';
        EXECUTE 'CREATE POLICY marketing_manager_task_comments_insert ON public.task_comments FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND public.can_marketing_manager_edit_task(task_id, auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS marketing_manager_task_comments_update ON public.task_comments';
        EXECUTE 'CREATE POLICY marketing_manager_task_comments_update ON public.task_comments FOR UPDATE TO authenticated USING (public.can_marketing_manager_edit_task(task_id, auth.uid())) WITH CHECK (public.can_marketing_manager_edit_task(task_id, auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS marketing_manager_task_comments_delete ON public.task_comments';
        EXECUTE 'CREATE POLICY marketing_manager_task_comments_delete ON public.task_comments FOR DELETE TO authenticated USING (public.can_marketing_manager_edit_task(task_id, auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS mq20_no_task_comments_insert ON public.task_comments';
        EXECUTE 'CREATE POLICY mq20_no_task_comments_insert ON public.task_comments AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (NOT public.is_mq20_profile(auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS mq20_no_task_comments_update ON public.task_comments';
        EXECUTE 'CREATE POLICY mq20_no_task_comments_update ON public.task_comments AS RESTRICTIVE FOR UPDATE TO authenticated USING (NOT public.is_mq20_profile(auth.uid())) WITH CHECK (NOT public.is_mq20_profile(auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS mq20_no_task_comments_delete ON public.task_comments';
        EXECUTE 'CREATE POLICY mq20_no_task_comments_delete ON public.task_comments AS RESTRICTIVE FOR DELETE TO authenticated USING (NOT public.is_mq20_profile(auth.uid()))';
    END IF;

    IF to_regclass('public.task_attachments') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS marketing_and_granted_task_attachments_select ON public.task_attachments';
        EXECUTE 'CREATE POLICY marketing_and_granted_task_attachments_select ON public.task_attachments FOR SELECT TO authenticated USING (public.can_view_task_via_employee_grant(task_id, auth.uid()) OR public.can_marketing_manager_edit_task(task_id, auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS mq20_only_ines_task_attachments_select ON public.task_attachments';
        EXECUTE 'CREATE POLICY mq20_only_ines_task_attachments_select ON public.task_attachments AS RESTRICTIVE FOR SELECT TO authenticated USING (NOT public.is_mq20_profile(auth.uid()) OR public.is_ines_modani_task(task_id))';
        EXECUTE 'DROP POLICY IF EXISTS marketing_manager_task_attachments_insert ON public.task_attachments';
        EXECUTE 'CREATE POLICY marketing_manager_task_attachments_insert ON public.task_attachments FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid() AND public.can_marketing_manager_edit_task(task_id, auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS marketing_manager_task_attachments_update ON public.task_attachments';
        EXECUTE 'CREATE POLICY marketing_manager_task_attachments_update ON public.task_attachments FOR UPDATE TO authenticated USING (public.can_marketing_manager_edit_task(task_id, auth.uid())) WITH CHECK (public.can_marketing_manager_edit_task(task_id, auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS marketing_manager_task_attachments_delete ON public.task_attachments';
        EXECUTE 'CREATE POLICY marketing_manager_task_attachments_delete ON public.task_attachments FOR DELETE TO authenticated USING (public.can_marketing_manager_edit_task(task_id, auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS mq20_no_task_attachments_insert ON public.task_attachments';
        EXECUTE 'CREATE POLICY mq20_no_task_attachments_insert ON public.task_attachments AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (NOT public.is_mq20_profile(auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS mq20_no_task_attachments_update ON public.task_attachments';
        EXECUTE 'CREATE POLICY mq20_no_task_attachments_update ON public.task_attachments AS RESTRICTIVE FOR UPDATE TO authenticated USING (NOT public.is_mq20_profile(auth.uid())) WITH CHECK (NOT public.is_mq20_profile(auth.uid()))';
        EXECUTE 'DROP POLICY IF EXISTS mq20_no_task_attachments_delete ON public.task_attachments';
        EXECUTE 'CREATE POLICY mq20_no_task_attachments_delete ON public.task_attachments AS RESTRICTIVE FOR DELETE TO authenticated USING (NOT public.is_mq20_profile(auth.uid()))';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_task_employee_access_grants()
RETURNS TABLE (
    viewer_id uuid,
    subject_id uuid,
    granted_by uuid,
    created_at timestamptz,
    is_locked boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT access.viewer_id,
           access.subject_id,
           access.granted_by,
           access.created_at,
           public.is_mq20_profile(access.viewer_id) AND public.is_ines_modani_profile(access.subject_id)
    FROM public.task_employee_access_grants access
    WHERE access.viewer_id = auth.uid()
       OR public.is_marketing_task_manager(auth.uid())
    ORDER BY access.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.set_task_employee_access_grant(
    p_viewer_id uuid,
    p_subject_id uuid,
    p_enabled boolean DEFAULT true
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.is_marketing_task_manager(auth.uid()) THEN
        RAISE EXCEPTION 'Only the Marketing Manager can manage employee task viewing access'
            USING ERRCODE = '42501';
    END IF;

    IF p_viewer_id = p_subject_id THEN
        RAISE EXCEPTION 'Viewer and task owner must be different employees'
            USING ERRCODE = '23514';
    END IF;

    IF public.is_mq20_profile(p_viewer_id) THEN
        IF NOT public.is_ines_modani_profile(p_subject_id) OR NOT p_enabled THEN
            RAISE EXCEPTION 'MQ-20 has fixed view-only access to Ines Modani tasks'
                USING ERRCODE = '42501';
        END IF;
    ELSIF NOT public.is_sales_marketing_employee(p_viewer_id)
       OR NOT public.is_sales_marketing_employee(p_subject_id) THEN
        RAISE EXCEPTION 'Both employees must belong to Sales or Marketing'
            USING ERRCODE = '42501';
    END IF;

    IF p_enabled THEN
        INSERT INTO public.task_employee_access_grants (viewer_id, subject_id, granted_by)
        VALUES (p_viewer_id, p_subject_id, auth.uid())
        ON CONFLICT (viewer_id, subject_id) DO UPDATE
        SET granted_by = EXCLUDED.granted_by, updated_at = now();
    ELSE
        DELETE FROM public.task_employee_access_grants
        WHERE viewer_id = p_viewer_id AND subject_id = p_subject_id;
    END IF;

    RETURN true;
END;
$$;

-- Seed the fixed MQ-20 -> Ines Modani access requested for this deployment.
INSERT INTO public.task_employee_access_grants (viewer_id, subject_id, granted_by)
SELECT mq20.id,
       ines.id,
       (
           SELECT manager.id
           FROM public.profiles manager
           WHERE public.is_marketing_task_manager(manager.id)
           ORDER BY manager.created_at NULLS LAST
           LIMIT 1
       )
FROM public.profiles mq20
CROSS JOIN LATERAL (
    SELECT candidate.id
    FROM public.profiles candidate
    WHERE public.is_ines_modani_profile(candidate.id)
    ORDER BY candidate.created_at NULLS LAST
    LIMIT 1
) ines
WHERE UPPER(BTRIM(COALESCE(mq20.employee_id, ''))) = 'MQ-20'
  AND mq20.is_active IS DISTINCT FROM false
ON CONFLICT (viewer_id, subject_id) DO UPDATE SET updated_at = now();

REVOKE ALL ON FUNCTION public.is_marketing_task_manager(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_sales_marketing_employee(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_marketing_managed_task_list(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.task_belongs_to_employee(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_view_task_via_employee_grant(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_view_task_list_via_employee_grant(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_marketing_manager_edit_task(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_mq20_profile(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_ines_modani_profile(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_ines_modani_task(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_ines_modani_task_list(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_task_employee_access_grants() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_task_employee_access_grant(uuid, uuid, boolean) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_task_employee_access_grants() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_task_employee_access_grant(uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_marketing_task_manager(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_sales_marketing_employee(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_marketing_managed_task_list(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.task_belongs_to_employee(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_task_via_employee_grant(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_task_list_via_employee_grant(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_marketing_manager_edit_task(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_mq20_profile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_ines_modani_profile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_ines_modani_task(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_ines_modani_task_list(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
