-- Task-only authoritative service boundary for web and future native clients.
-- All mutations run as SECURITY DEFINER functions with explicit authorization;
-- direct table access remains subject to the existing RLS policies.
BEGIN;

-- Force all authenticated Task Manager writes through the RPC façade. Read
-- access remains governed by the existing task RLS policies; SECURITY DEFINER
-- RPCs perform the validated writes on behalf of the caller.
REVOKE INSERT, UPDATE, DELETE ON public.tasks FROM authenticated;

CREATE OR REPLACE FUNCTION public.can_access_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tasks task
    WHERE task.id = p_task_id
      AND p_user_id IS NOT NULL
      AND (
        task.created_by = p_user_id
        OR task.assignee_id = p_user_id
        OR task.supervisor_id = p_user_id
        OR p_user_id = ANY(COALESCE(task.assignee_ids, '{}'::uuid[]))
        OR p_user_id = ANY(COALESCE(task.visible_to, '{}'::uuid[]))
        OR public.can_assign_tasks_company_wide(p_user_id)
        OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list(task.task_list_id, p_user_id))
        OR (task.task_list_id IS NOT NULL AND public.can_view_task_list_via_employee_grant(task.task_list_id, p_user_id))
      )
  );
$$;

DROP POLICY IF EXISTS task_secure_access_select ON public.tasks;
CREATE POLICY task_secure_access_select ON public.tasks AS RESTRICTIVE
  FOR SELECT TO authenticated
  USING (public.can_access_task(id, auth.uid()));

CREATE OR REPLACE FUNCTION public.can_manage_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tasks task
    LEFT JOIN public.task_lists list ON list.id = task.task_list_id
    WHERE task.id = p_task_id
      AND p_user_id IS NOT NULL
      AND (
        task.created_by = p_user_id
        OR task.supervisor_id = p_user_id
        OR public.can_assign_tasks_company_wide(p_user_id)
        OR public.can_marketing_manager_edit_task(p_task_id, p_user_id)
        OR p_user_id = ANY(COALESCE(list.can_delete_users, '{}'::uuid[]))
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.list_accessible_tasks_secure()
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT to_jsonb(task)
    || jsonb_build_object(
      'assignee', CASE WHEN profile.id IS NULL THEN NULL ELSE jsonb_build_object('id', profile.id, 'full_name', profile.full_name, 'display_name', profile.display_name, 'display_name_ar', profile.display_name_ar, 'role', profile.role, 'job_title', profile.job_title, 'employee_id', profile.employee_id) END,
      'profiles', CASE WHEN profile.id IS NULL THEN NULL ELSE jsonb_build_object('id', profile.id, 'full_name', profile.full_name, 'display_name', profile.display_name, 'display_name_ar', profile.display_name_ar, 'role', profile.role, 'job_title', profile.job_title, 'employee_id', profile.employee_id) END,
      'projects', CASE WHEN project.id IS NULL THEN NULL ELSE jsonb_build_object('id', project.id, 'project_name', project.project_name) END
    )
  FROM public.tasks task
  LEFT JOIN public.profiles profile ON profile.id = task.assignee_id
  LEFT JOIN public.projects project ON project.id = task.project_id
  WHERE auth.uid() IS NOT NULL AND public.can_access_task(task.id, auth.uid())
  ORDER BY task.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_task_secure(p_task_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT item FROM public.list_accessible_tasks_secure() item
  WHERE item->>'id' = p_task_id::text LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.add_task_comment(
  p_task_id uuid, p_content text, p_attachments jsonb DEFAULT '[]'::jsonb
)
RETURNS public.task_comments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE result_row public.task_comments;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_access_task(p_task_id, auth.uid()) THEN
    RAISE EXCEPTION 'Task access denied' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_content, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Comment text is required' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(COALESCE(p_attachments, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Comment attachments must be an array' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(p_attachments, '[]'::jsonb)) item
    WHERE jsonb_typeof(item) <> 'object'
       OR COALESCE(item->>'url', item->>'file_url', '') !~ ('^storage://task-attachments/' || p_task_id::text || '/[A-Za-z0-9._/-]+$')) THEN
    RAISE EXCEPTION 'Comment attachments must reference private task storage' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.task_comments(task_id, user_id, content, attachments)
  VALUES (p_task_id, auth.uid(), BTRIM(p_content), COALESCE(p_attachments, '[]'::jsonb))
  RETURNING * INTO result_row;
  RETURN result_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_task_comment(
  p_comment_id uuid, p_content text, p_attachments jsonb DEFAULT NULL
)
RETURNS public.task_comments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE existing_row public.task_comments; result_row public.task_comments;
BEGIN
  SELECT * INTO existing_row FROM public.task_comments WHERE id = p_comment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Comment not found' USING ERRCODE = 'P0002'; END IF;
  IF auth.uid() IS NULL OR NOT (existing_row.user_id = auth.uid() OR public.can_manage_task(existing_row.task_id, auth.uid())) THEN
    RAISE EXCEPTION 'Comment access denied' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(BTRIM(COALESCE(p_content, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Comment text is required' USING ERRCODE = '22023';
  END IF;
  IF p_attachments IS NOT NULL AND jsonb_typeof(p_attachments) <> 'array' THEN
    RAISE EXCEPTION 'Comment attachments must be an array' USING ERRCODE = '22023';
  END IF;
  IF p_attachments IS NOT NULL AND EXISTS (SELECT 1 FROM jsonb_array_elements(p_attachments) item
    WHERE jsonb_typeof(item) <> 'object'
       OR COALESCE(item->>'url', item->>'file_url', '') !~ ('^storage://task-attachments/' || existing_row.task_id::text || '/[A-Za-z0-9._/-]+$')) THEN
    RAISE EXCEPTION 'Comment attachments must reference private task storage' USING ERRCODE = '22023';
  END IF;
  UPDATE public.task_comments SET content = BTRIM(p_content),
    attachments = COALESCE(p_attachments, attachments), edited_at = now()
  WHERE id = p_comment_id RETURNING * INTO result_row;
  RETURN result_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_task_comment(p_comment_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE existing_row public.task_comments;
BEGIN
  SELECT * INTO existing_row FROM public.task_comments WHERE id = p_comment_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF auth.uid() IS NULL OR NOT (existing_row.user_id = auth.uid() OR public.can_manage_task(existing_row.task_id, auth.uid())) THEN
    RAISE EXCEPTION 'Comment access denied' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.task_comments WHERE id = p_comment_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_task_comments_secure(p_task_id uuid)
RETURNS SETOF public.task_comments
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT * FROM public.task_comments
  WHERE task_id = p_task_id AND auth.uid() IS NOT NULL AND public.can_access_task(p_task_id, auth.uid())
  ORDER BY created_at ASC;
$$;

-- Remove the historical globally-readable policies. These policies are
-- intentionally task-scoped; the RPCs above derive actor identity from auth.uid().
DROP POLICY IF EXISTS "task_comments_select" ON public.task_comments;
DROP POLICY IF EXISTS "task_comments_insert" ON public.task_comments;
DROP POLICY IF EXISTS "task_comments_update" ON public.task_comments;
DROP POLICY IF EXISTS "task_comments_delete" ON public.task_comments;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.task_comments;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.task_comments;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON public.task_comments;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON public.task_comments;
DROP POLICY IF EXISTS marketing_and_granted_task_comments_select ON public.task_comments;
DROP POLICY IF EXISTS mq20_only_ines_task_comments_select ON public.task_comments;
DROP POLICY IF EXISTS marketing_and_granted_task_comments_insert ON public.task_comments;
DROP POLICY IF EXISTS marketing_and_granted_task_comments_update ON public.task_comments;
DROP POLICY IF EXISTS marketing_and_granted_task_comments_delete ON public.task_comments;
CREATE POLICY task_comments_secure_select ON public.task_comments FOR SELECT TO authenticated
  USING (public.can_access_task(task_id, auth.uid()));
CREATE POLICY task_comments_secure_insert ON public.task_comments FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.can_access_task(task_id, auth.uid()));
CREATE POLICY task_comments_secure_update ON public.task_comments FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.can_manage_task(task_id, auth.uid()))
  WITH CHECK (user_id = auth.uid() OR public.can_manage_task(task_id, auth.uid()));
CREATE POLICY task_comments_secure_delete ON public.task_comments FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR public.can_manage_task(task_id, auth.uid()));
-- Preserve the existing MQ-20 observer restriction while replacing only the
-- globally-readable policy.
CREATE POLICY mq20_only_ines_task_comments_select ON public.task_comments AS RESTRICTIVE
  FOR SELECT TO authenticated
  USING (NOT public.is_mq20_profile(auth.uid()) OR public.is_ines_modani_task(task_id));

-- Remove the legacy attachment policies that allowed any authenticated user to
-- read/insert/delete arbitrary task files. Metadata and storage object access
-- now use the same task predicates as the RPC boundary.
DROP POLICY IF EXISTS "Users can view task attachments" ON public.task_attachments;
DROP POLICY IF EXISTS "Authenticated users can upload attachments" ON public.task_attachments;
DROP POLICY IF EXISTS "Uploaders can delete their attachments" ON public.task_attachments;
DROP POLICY IF EXISTS task_attachments_insert_secure ON public.task_attachments;
DROP POLICY IF EXISTS task_attachments_update_secure ON public.task_attachments;
DROP POLICY IF EXISTS task_attachments_delete_secure ON public.task_attachments;
CREATE POLICY task_attachments_insert_secure ON public.task_attachments FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.can_manage_task_attachments(task_id, auth.uid()));
CREATE POLICY task_attachments_update_secure ON public.task_attachments FOR UPDATE TO authenticated
  USING (public.can_manage_task_attachments(task_id, auth.uid()))
  WITH CHECK (public.can_manage_task_attachments(task_id, auth.uid()));
CREATE POLICY task_attachments_delete_secure ON public.task_attachments FOR DELETE TO authenticated
  USING (public.can_manage_task_attachments(task_id, auth.uid()));

-- Storage writes are namespaced as <task-id>/<uploader-id>/<file>. The bucket
-- stays private and the task predicate is checked before accepting an object.
DROP POLICY IF EXISTS "Authenticated users can upload task attachments" ON storage.objects;
DROP POLICY IF EXISTS task_attachment_storage_insert_secure ON storage.objects;
CREATE POLICY task_attachment_storage_insert_secure ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'task-attachments'
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND public.can_manage_task_attachments(((storage.foldername(name))[1])::uuid, auth.uid())
  );
DROP POLICY IF EXISTS task_attachment_storage_update_secure ON storage.objects;
CREATE POLICY task_attachment_storage_update_secure ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'task-attachments'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND public.can_manage_task_attachments(((storage.foldername(name))[1])::uuid, auth.uid())
  )
  WITH CHECK (
    bucket_id = 'task-attachments'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND public.can_manage_task_attachments(((storage.foldername(name))[1])::uuid, auth.uid())
  );
DROP POLICY IF EXISTS task_attachment_storage_delete_secure ON storage.objects;
CREATE POLICY task_attachment_storage_delete_secure ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'task-attachments'
    AND (storage.foldername(name))[2] = auth.uid()::text
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND public.can_manage_task_attachments(((storage.foldername(name))[1])::uuid, auth.uid())
  );

CREATE OR REPLACE FUNCTION public.register_task_attachment(
  p_task_id uuid, p_file_url text, p_file_name text, p_file_type text DEFAULT NULL,
  p_file_size bigint DEFAULT NULL, p_attachment_scope text DEFAULT 'TASK',
  p_visible boolean DEFAULT false
)
RETURNS public.task_attachments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE result_row public.task_attachments; scope_value text := UPPER(BTRIM(COALESCE(p_attachment_scope, 'TASK')));
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_task_attachments(p_task_id, auth.uid()) THEN
    RAISE EXCEPTION 'Task attachment access denied' USING ERRCODE = '42501';
  END IF;
  IF scope_value NOT IN ('TASK', 'COMMENT') OR NULLIF(BTRIM(COALESCE(p_file_url, '')), '') IS NULL OR NULLIF(BTRIM(COALESCE(p_file_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Attachment metadata is invalid' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.task_attachments(task_id, user_id, file_url, file_name, file_type, file_size, attachment_scope, visible_to_project_assignee)
  VALUES (p_task_id, auth.uid(), BTRIM(p_file_url), BTRIM(p_file_name), NULLIF(BTRIM(p_file_type), ''), p_file_size, scope_value, COALESCE(p_visible, false))
  RETURNING * INTO result_row;
  RETURN result_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_task_attachments_secure(p_task_id uuid, p_scope text DEFAULT NULL)
RETURNS SETOF jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object('id', id, 'task_id', task_id, 'file_url', file_url,
    'storage_reference', file_url, 'file_name', file_name, 'file_type', file_type,
    'file_size', file_size, 'attachment_scope', attachment_scope,
    'visible_to_project_assignee', visible_to_project_assignee, 'created_at', created_at)
  FROM public.task_attachments
  WHERE task_id = p_task_id AND is_archived = false
    AND (p_scope IS NULL OR attachment_scope = UPPER(p_scope))
    AND auth.uid() IS NOT NULL AND public.can_access_task(p_task_id, auth.uid())
  ORDER BY created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.remove_task_attachment(p_attachment_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE task_value uuid;
BEGIN
  SELECT task_id INTO task_value FROM public.task_attachments WHERE id = p_attachment_id FOR UPDATE;
  IF task_value IS NULL THEN RETURN false; END IF;
  IF auth.uid() IS NULL OR NOT public.can_manage_task_attachments(task_value, auth.uid()) THEN
    RAISE EXCEPTION 'Task attachment access denied' USING ERRCODE = '42501';
  END IF;
  UPDATE public.task_attachments SET is_archived = true, archived_at = now(), archived_by = auth.uid(), visible_to_project_assignee = false
  WHERE id = p_attachment_id AND is_archived = false;
  RETURN FOUND;
END;
$$;

CREATE TABLE IF NOT EXISTS public.task_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid NOT NULL,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  action text NOT NULL,
  from_status text,
  to_status text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS task_activity_task_created_idx ON public.task_activity(task_id, created_at DESC);
ALTER TABLE public.task_activity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS task_activity_secure_select ON public.task_activity;
CREATE POLICY task_activity_secure_select ON public.task_activity FOR SELECT TO authenticated
  USING (public.can_access_task(task_id, auth.uid()));

CREATE OR REPLACE FUNCTION public.record_task_activity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.task_activity(task_id, actor_id, action, metadata) VALUES (NEW.id, auth.uid(), 'TASK_CREATED', '{}'::jsonb);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      INSERT INTO public.task_activity(task_id, actor_id, action, from_status, to_status) VALUES (NEW.id, auth.uid(), 'TASK_STATUS_CHANGED', OLD.status, NEW.status);
    END IF;
    IF NEW.assignee_id IS DISTINCT FROM OLD.assignee_id OR NEW.assignee_ids IS DISTINCT FROM OLD.assignee_ids THEN
      INSERT INTO public.task_activity(task_id, actor_id, action, metadata) VALUES (NEW.id, auth.uid(), 'TASK_ASSIGNED', jsonb_build_object('assignee_id', NEW.assignee_id, 'assignee_ids', NEW.assignee_ids));
    END IF;
    RETURN NEW;
  ELSE
    INSERT INTO public.task_activity(task_id, actor_id, action, metadata) VALUES (OLD.id, auth.uid(), 'TASK_DELETED', jsonb_build_object('title', OLD.title));
    RETURN OLD;
  END IF;
END;
$$;
DROP TRIGGER IF EXISTS task_activity_after_insert ON public.tasks;
CREATE TRIGGER task_activity_after_insert AFTER INSERT ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();
DROP TRIGGER IF EXISTS task_activity_after_update ON public.tasks;
CREATE TRIGGER task_activity_after_update AFTER UPDATE OF status, assignee_id, assignee_ids ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();
DROP TRIGGER IF EXISTS task_activity_before_delete ON public.tasks;
CREATE TRIGGER task_activity_before_delete BEFORE DELETE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();

CREATE OR REPLACE FUNCTION public.record_task_child_activity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE task_value uuid := COALESCE(NEW.task_id, OLD.task_id); action_value text;
BEGIN
  action_value := CASE WHEN TG_TABLE_NAME = 'task_comments' THEN CASE TG_OP WHEN 'INSERT' THEN 'COMMENT_ADDED' WHEN 'UPDATE' THEN 'COMMENT_EDITED' ELSE 'COMMENT_DELETED' END ELSE CASE TG_OP WHEN 'INSERT' THEN 'ATTACHMENT_ADDED' ELSE 'ATTACHMENT_ARCHIVED' END END;
  INSERT INTO public.task_activity(task_id, actor_id, action, metadata) VALUES (task_value, auth.uid(), action_value, jsonb_build_object('record_id', COALESCE(NEW.id, OLD.id)));
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
DROP TRIGGER IF EXISTS task_comment_activity ON public.task_comments;
CREATE TRIGGER task_comment_activity AFTER INSERT OR UPDATE OR DELETE ON public.task_comments FOR EACH ROW EXECUTE FUNCTION public.record_task_child_activity();
DROP TRIGGER IF EXISTS task_attachment_activity ON public.task_attachments;
CREATE TRIGGER task_attachment_activity AFTER INSERT OR UPDATE OF is_archived ON public.task_attachments FOR EACH ROW EXECUTE FUNCTION public.record_task_child_activity();

CREATE OR REPLACE FUNCTION public.list_task_activity_secure(p_task_id uuid)
RETURNS SETOF public.task_activity
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT * FROM public.task_activity WHERE task_id = p_task_id
    AND auth.uid() IS NOT NULL AND public.can_access_task(p_task_id, auth.uid())
  ORDER BY created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.can_access_task(uuid, uuid), public.can_manage_task(uuid, uuid), public.list_accessible_tasks_secure(), public.get_task_secure(uuid), public.create_task_secure(jsonb), public.update_task_secure(uuid, jsonb), public.delete_task_secure(uuid), public.add_task_comment(uuid, text, jsonb), public.update_task_comment(uuid, text, jsonb), public.delete_task_comment(uuid), public.list_task_comments_secure(uuid), public.register_task_attachment(uuid, text, text, text, bigint, text, boolean), public.list_task_attachments_secure(uuid, text), public.remove_task_attachment(uuid), public.list_task_activity_secure(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_task(uuid, uuid), public.can_manage_task(uuid, uuid), public.list_accessible_tasks_secure(), public.get_task_secure(uuid), public.create_task_secure(jsonb), public.update_task_secure(uuid, jsonb), public.delete_task_secure(uuid), public.add_task_comment(uuid, text, jsonb), public.update_task_comment(uuid, text, jsonb), public.delete_task_comment(uuid), public.list_task_comments_secure(uuid), public.register_task_attachment(uuid, text, text, text, bigint, text, boolean), public.list_task_attachments_secure(uuid, text), public.remove_task_attachment(uuid), public.list_task_activity_secure(uuid) TO authenticated;
GRANT SELECT ON public.task_activity TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
