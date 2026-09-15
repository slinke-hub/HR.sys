-- Archive replaced task/order attachments and expose only explicitly shared
-- current files to project assignees.
BEGIN;

ALTER TABLE public.crm_deal_attachments
    ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS visible_to_project_assignee BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.task_attachments
    ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS visible_to_project_assignee BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS attachment_scope TEXT NOT NULL DEFAULT 'TASK';

ALTER TABLE public.task_attachments
    DROP CONSTRAINT IF EXISTS task_attachments_attachment_scope_check;
ALTER TABLE public.task_attachments
    ADD CONSTRAINT task_attachments_attachment_scope_check
    CHECK (attachment_scope IN ('TASK', 'COMMENT'));

UPDATE public.task_attachments attachment
SET attachment_scope = 'COMMENT'
WHERE EXISTS (
    SELECT 1
    FROM public.task_comments comment
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(comment.attachments, '[]'::JSONB)) item
    WHERE comment.task_id = attachment.task_id
      AND COALESCE(item->>'url', item->>'file_url', CASE WHEN jsonb_typeof(item) = 'string' THEN item #>> '{}' END) = attachment.file_url
);

CREATE INDEX IF NOT EXISTS crm_deal_attachments_current_idx
    ON public.crm_deal_attachments(deal_id, category, created_at DESC)
    WHERE is_archived = FALSE;
CREATE INDEX IF NOT EXISTS task_attachments_current_idx
    ON public.task_attachments(task_id, created_at DESC)
    WHERE is_archived = FALSE;

CREATE OR REPLACE FUNCTION public.can_manage_task_attachments(
    p_task_id UUID,
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
        FROM public.tasks task
        LEFT JOIN public.projects project ON project.id = task.project_id
        WHERE task.id = p_task_id
          AND (
              task.created_by = p_user_id
              OR task.assignee_id = p_user_id
              OR p_user_id = ANY(COALESCE(task.assignee_ids, ARRAY[]::UUID[]))
              OR task.supervisor_id = p_user_id
              OR project.created_by = p_user_id
              OR project.project_manager_id = p_user_id
              OR public.is_project_portfolio_admin(p_user_id)
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.archive_crm_deal_attachments(
    p_deal_id UUID,
    p_categories TEXT[],
    p_keep_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to replace deal attachments';
    END IF;

    UPDATE public.crm_deal_attachments
       SET is_archived = TRUE,
           archived_at = NOW(),
           archived_by = auth.uid(),
           visible_to_project_assignee = FALSE
     WHERE deal_id = p_deal_id
       AND is_archived = FALSE
       AND UPPER(category) = ANY(COALESCE(p_categories, ARRAY[]::TEXT[]))
       AND NOT (id = ANY(COALESCE(p_keep_ids, ARRAY[]::UUID[])));
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_task_attachments(
    p_task_id UUID,
    p_keep_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_manage_task_attachments(p_task_id, auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to replace task attachments';
    END IF;

    UPDATE public.task_attachments
       SET is_archived = TRUE,
           archived_at = NOW(),
           archived_by = auth.uid(),
           visible_to_project_assignee = FALSE
     WHERE task_id = p_task_id
       AND is_archived = FALSE
       AND attachment_scope = 'TASK'
       AND NOT (id = ANY(COALESCE(p_keep_ids, ARRAY[]::UUID[])));
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_project_attachment_visibility(
    p_attachment_type TEXT,
    p_attachment_id UUID,
    p_visible BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_type TEXT := UPPER(BTRIM(COALESCE(p_attachment_type, '')));
    v_task_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF v_type = 'DEAL' THEN
        IF NOT public.can_access_crm(auth.uid()) THEN
            RAISE EXCEPTION 'Not authorized to manage deal attachments';
        END IF;
        UPDATE public.crm_deal_attachments
           SET visible_to_project_assignee = COALESCE(p_visible, FALSE)
         WHERE id = p_attachment_id AND is_archived = FALSE;
        RETURN FOUND;
    ELSIF v_type = 'TASK' THEN
        SELECT task_id INTO v_task_id
        FROM public.task_attachments
        WHERE id = p_attachment_id AND is_archived = FALSE;
        IF v_task_id IS NULL OR NOT public.can_manage_task_attachments(v_task_id, auth.uid()) THEN
            RAISE EXCEPTION 'Not authorized to manage task attachments';
        END IF;
        UPDATE public.task_attachments
           SET visible_to_project_assignee = COALESCE(p_visible, FALSE)
         WHERE id = p_attachment_id AND is_archived = FALSE;
        RETURN FOUND;
    END IF;

    RAISE EXCEPTION 'Unsupported attachment type';
END;
$$;

DROP FUNCTION IF EXISTS public.list_project_shared_attachments(UUID);
CREATE FUNCTION public.list_project_shared_attachments(p_project_id UUID)
RETURNS TABLE (
    attachment_type TEXT,
    attachment_id UUID,
    source_id UUID,
    category TEXT,
    file_name TEXT,
    file_url TEXT,
    file_type TEXT,
    description TEXT,
    created_at TIMESTAMPTZ,
    visible_to_project_assignee BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_manager BOOLEAN;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project not found or access denied';
    END IF;

    SELECT (
        project.created_by = auth.uid()
        OR project.project_manager_id = auth.uid()
        OR public.is_project_portfolio_admin(auth.uid())
    )
    INTO v_is_manager
    FROM public.projects project
    WHERE project.id = p_project_id;

    RETURN QUERY
    SELECT
        'DEAL'::TEXT,
        attachment.id,
        attachment.deal_id,
        attachment.category,
        attachment.file_name,
        attachment.file_url,
        NULL::TEXT,
        attachment.description,
        attachment.created_at,
        attachment.visible_to_project_assignee
    FROM public.projects project
    JOIN public.crm_deal_attachments attachment ON attachment.deal_id = project.deal_id
    WHERE project.id = p_project_id
      AND attachment.is_archived = FALSE
      AND (v_is_manager OR attachment.visible_to_project_assignee)

    UNION ALL

    SELECT
        'TASK'::TEXT,
        attachment.id,
        attachment.task_id,
        'TASK'::TEXT,
        attachment.file_name,
        attachment.file_url,
        attachment.file_type,
        NULL::TEXT,
        attachment.created_at,
        attachment.visible_to_project_assignee
    FROM public.task_attachments attachment
    JOIN public.tasks task ON task.id = attachment.task_id
    JOIN public.projects project ON project.id = p_project_id
    WHERE attachment.is_archived = FALSE
      AND attachment.attachment_scope = 'TASK'
      AND (task.project_id = project.id OR (project.deal_id IS NOT NULL AND task.crm_deal_id = project.deal_id))
      AND (v_is_manager OR attachment.visible_to_project_assignee)
    ORDER BY 9 DESC;
END;
$$;

-- Replace the legacy globally-readable task attachment policy with scoped access.
DROP POLICY IF EXISTS "Users can view task attachments" ON public.task_attachments;
DROP POLICY IF EXISTS task_attachment_versioned_select ON public.task_attachments;
CREATE POLICY task_attachment_versioned_select
ON public.task_attachments FOR SELECT TO authenticated
USING (
    public.can_manage_task_attachments(task_id, auth.uid())
    OR (
        is_archived = FALSE
        AND visible_to_project_assignee = TRUE
        AND EXISTS (
            SELECT 1
            FROM public.tasks task
            JOIN public.projects project
              ON project.id = task.project_id
              OR (project.deal_id IS NOT NULL AND project.deal_id = task.crm_deal_id)
            WHERE task.id = task_attachments.task_id
              AND auth.uid() = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
        )
    )
);

DROP POLICY IF EXISTS crm_project_shared_attachments_select ON public.crm_deal_attachments;
CREATE POLICY crm_project_shared_attachments_select
ON public.crm_deal_attachments FOR SELECT TO authenticated
USING (
    is_archived = FALSE
    AND visible_to_project_assignee = TRUE
    AND EXISTS (
        SELECT 1
        FROM public.projects project
        WHERE project.deal_id = crm_deal_attachments.deal_id
          AND auth.uid() = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
    )
);

DROP POLICY IF EXISTS sensitive_crm_deal_files_read ON storage.objects;
CREATE POLICY sensitive_crm_deal_files_read
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'crm-deal-files'
    AND (
        public.can_access_crm(auth.uid())
        OR EXISTS (
            SELECT 1
            FROM public.crm_deal_attachments attachment
            JOIN public.projects project ON project.deal_id = attachment.deal_id
            WHERE attachment.file_url = 'storage://crm-deal-files/' || storage.objects.name
              AND attachment.is_archived = FALSE
              AND attachment.visible_to_project_assignee = TRUE
              AND auth.uid() = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
        )
    )
);

DROP POLICY IF EXISTS sensitive_task_attachments_read ON storage.objects;
CREATE POLICY sensitive_task_attachments_read
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'task-attachments'
    AND EXISTS (
        SELECT 1
        FROM public.task_attachments attachment
        LEFT JOIN public.tasks task ON task.id = attachment.task_id
        LEFT JOIN public.projects project
          ON project.id = task.project_id
          OR (project.deal_id IS NOT NULL AND project.deal_id = task.crm_deal_id)
        WHERE attachment.file_url = 'storage://task-attachments/' || storage.objects.name
          AND (
              public.can_manage_task_attachments(attachment.task_id, auth.uid())
              OR (
                  attachment.is_archived = FALSE
                  AND attachment.visible_to_project_assignee = TRUE
                  AND auth.uid() = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
              )
          )
    )
);

GRANT UPDATE ON public.crm_deal_attachments, public.task_attachments TO authenticated;
REVOKE ALL ON FUNCTION public.can_manage_task_attachments(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.archive_crm_deal_attachments(UUID, TEXT[], UUID[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.archive_task_attachments(UUID, UUID[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_project_attachment_visibility(TEXT, UUID, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_project_shared_attachments(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_task_attachments(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_crm_deal_attachments(UUID, TEXT[], UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_task_attachments(UUID, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_project_attachment_visibility(TEXT, UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_project_shared_attachments(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
