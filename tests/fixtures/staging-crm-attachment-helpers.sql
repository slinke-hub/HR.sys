-- Exact attachment authorization helper definitions from the Staging
-- 2026-11-10 export. Synthetic test schema/data only.
CREATE OR REPLACE FUNCTION public.can_manage_task_attachments(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT p_user_id IS NOT NULL
    AND (auth.uid() IS NULL OR p_user_id = auth.uid())
    AND (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
    AND EXISTS (
      SELECT 1
      FROM public.tasks task
      LEFT JOIN public.projects project ON project.id = task.project_id
      WHERE task.id = p_task_id
        AND (
          task.created_by = p_user_id
          OR task.assignee_id = p_user_id
          OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
          OR task.supervisor_id = p_user_id
          OR project.created_by = p_user_id
          OR project.project_manager_id = p_user_id
          OR public.is_project_portfolio_admin(p_user_id)
        )
    );
$function$;
ALTER FUNCTION public.can_manage_task_attachments(uuid,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.can_manage_task_attachments(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_task_attachments(uuid,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_read_task_attachment_file(p_object_name text, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF p_user_id IS NULL OR (auth.uid() IS NOT NULL AND p_user_id <> auth.uid()) THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1
    FROM public.task_attachments attachment
    JOIN public.tasks task ON task.id = attachment.task_id
    LEFT JOIN public.projects project ON project.id = task.project_id
    WHERE attachment.file_url = 'storage://task-attachments/' || p_object_name
      AND (
        public.can_access_task(task.id, p_user_id)
        OR (
          (auth.uid() IS NULL OR NOT public.is_mq20_profile(auth.uid()))
          AND project.id IS NOT NULL
          AND p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::uuid[]))
        )
      )
  );
END;
$function$;
ALTER FUNCTION public.can_read_task_attachment_file(text,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.can_read_task_attachment_file(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_task_attachment_file(text,uuid) TO authenticated, service_role;
