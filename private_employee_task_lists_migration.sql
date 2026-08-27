-- Private employee-owned task lists with explicit view-only sharing.
BEGIN;
SET LOCAL lock_timeout = '15s';
SET LOCAL statement_timeout = '120s';

CREATE TABLE IF NOT EXISTS public.task_lists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 80),
    shared_with UUID[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS task_lists_owner_id_idx ON public.task_lists(owner_id);
CREATE INDEX IF NOT EXISTS task_lists_shared_with_gin_idx ON public.task_lists USING gin(shared_with);
CREATE UNIQUE INDEX IF NOT EXISTS task_lists_owner_name_unique_idx ON public.task_lists(owner_id, lower(btrim(name)));

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS task_list_id UUID REFERENCES public.task_lists(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS tasks_task_list_id_idx ON public.tasks(task_list_id);

CREATE OR REPLACE FUNCTION public.validate_task_list_sharing()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE invalid_viewer UUID;
BEGIN
    NEW.shared_with := array_remove(COALESCE(NEW.shared_with,'{}'),NEW.owner_id);
    SELECT viewer_id INTO invalid_viewer
    FROM unnest(NEW.shared_with) viewer_id
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.profiles owner
        JOIN public.profiles viewer ON viewer.id=viewer_id
        WHERE owner.id=NEW.owner_id AND (
            viewer.department_id=owner.department_id
            OR viewer.id=owner.manager_id
            OR EXISTS(SELECT 1 FROM public.departments department WHERE department.id=owner.department_id AND department.head_id=viewer.id)
        )
    ) LIMIT 1;
    IF invalid_viewer IS NOT NULL THEN
        RAISE EXCEPTION 'Task lists can only be shared with the owner''s manager, supervisor, or department colleagues';
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS validate_task_list_sharing_trigger ON public.task_lists;
CREATE TRIGGER validate_task_list_sharing_trigger BEFORE INSERT OR UPDATE OF owner_id,shared_with ON public.task_lists
FOR EACH ROW EXECUTE FUNCTION public.validate_task_list_sharing();

CREATE OR REPLACE FUNCTION public.enforce_private_task_list_ownership()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE list_owner UUID;
BEGIN
    IF NEW.task_list_id IS NULL THEN RETURN NEW; END IF;
    SELECT owner_id INTO list_owner FROM public.task_lists WHERE id=NEW.task_list_id;
    IF list_owner IS NULL THEN RAISE EXCEPTION 'Task list not found'; END IF;
    IF auth.uid() IS DISTINCT FROM list_owner THEN RAISE EXCEPTION 'Only the list owner can add or move tasks in this list'; END IF;
    NEW.created_by := list_owner;
    NEW.assignee_id := list_owner;
    NEW.supervisor_id := NULL;
    NEW.visibility := 'private';
    NEW.visible_to := '{}';
    NEW.watchers := '{}';
    RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS enforce_private_task_list_ownership_trigger ON public.tasks;
CREATE TRIGGER enforce_private_task_list_ownership_trigger BEFORE INSERT OR UPDATE OF task_list_id,created_by,assignee_id,supervisor_id,visibility,visible_to,watchers ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.enforce_private_task_list_ownership();

CREATE OR REPLACE FUNCTION public.can_view_task_list(p_list_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.task_lists list
        WHERE list.id=p_list_id
          AND (list.owner_id=p_user_id OR p_user_id=ANY(COALESCE(list.shared_with,'{}')))
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_task_list(p_list_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
    SELECT EXISTS (SELECT 1 FROM public.task_lists list WHERE list.id=p_list_id AND list.owner_id=p_user_id);
$$;

ALTER TABLE public.task_lists ENABLE ROW LEVEL SECURITY;
DO $$ DECLARE item RECORD; BEGIN
    FOR item IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='task_lists'
    LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.task_lists',item.policyname); END LOOP;
END $$;
CREATE POLICY task_lists_select_owner_or_viewer ON public.task_lists FOR SELECT TO authenticated
    USING(public.can_view_task_list(id,auth.uid()));
CREATE POLICY task_lists_insert_owner ON public.task_lists FOR INSERT TO authenticated
    WITH CHECK(owner_id=auth.uid());
CREATE POLICY task_lists_update_owner ON public.task_lists FOR UPDATE TO authenticated
    USING(owner_id=auth.uid()) WITH CHECK(owner_id=auth.uid());
CREATE POLICY task_lists_delete_owner ON public.task_lists FOR DELETE TO authenticated
    USING(owner_id=auth.uid());

CREATE OR REPLACE FUNCTION public.can_view_task(p_task_id UUID,p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.tasks task
    LEFT JOIN public.projects project ON project.id=task.project_id
    LEFT JOIN public.profiles viewer ON viewer.id=p_user_id
    WHERE task.id=p_task_id AND p_user_id IS NOT NULL AND (
      (task.task_list_id IS NOT NULL AND public.can_view_task_list(task.task_list_id,p_user_id))
      OR (task.task_list_id IS NULL AND (
        (upper(COALESCE(viewer.role,''))='EMPLOYEE' AND (task.assignee_id=p_user_id OR p_user_id=ANY(COALESCE(task.watchers,'{}'))))
        OR (upper(COALESCE(viewer.role,''))<>'EMPLOYEE' AND (
          public.is_task_admin(p_user_id)
          OR p_user_id IN (task.created_by,task.assignee_id,task.supervisor_id)
          OR p_user_id=ANY(COALESCE(task.watchers,'{}'))
          OR p_user_id=ANY(COALESCE(task.visible_to,'{}'))
          OR p_user_id=ANY(COALESCE(project.assigned_people,'{}'))
          OR EXISTS(SELECT 1 FROM public.departments department WHERE department.name=task.department AND department.head_id=p_user_id)
          OR task.visibility='public'
          OR (task.visibility='team' AND EXISTS(
            SELECT 1 FROM public.profiles owner WHERE owner.id IN(task.created_by,task.assignee_id)
              AND (viewer.department_id=owner.department_id OR owner.manager_id=p_user_id OR viewer.manager_id=owner.manager_id)
          ))
        ))
      ))
    )
  );
$$;

DROP POLICY IF EXISTS tasks_insert_own ON public.tasks;
CREATE POLICY tasks_insert_own ON public.tasks FOR INSERT TO authenticated
WITH CHECK(
    created_by=auth.uid()
    AND (task_list_id IS NULL OR public.can_manage_task_list(task_list_id,auth.uid()))
    AND (parent_task_id IS NULL OR public.can_view_task(parent_task_id,auth.uid()))
);

CREATE OR REPLACE FUNCTION public.can_manage_task(p_task_id UUID,p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.tasks task JOIN public.profiles viewer ON viewer.id=p_user_id
    WHERE task.id=p_task_id AND (
      (task.task_list_id IS NOT NULL AND public.can_manage_task_list(task.task_list_id,p_user_id))
      OR (task.task_list_id IS NULL AND (
        (upper(COALESCE(viewer.role,''))='EMPLOYEE' AND task.assignee_id=p_user_id)
        OR (upper(COALESCE(viewer.role,''))<>'EMPLOYEE' AND (
          public.is_task_admin(p_user_id) OR p_user_id IN(task.created_by,task.assignee_id,task.supervisor_id)
          OR EXISTS(SELECT 1 FROM public.departments department WHERE department.name=task.department AND department.head_id=p_user_id)
        ))
      ))
    )
  );
$$;

DROP POLICY IF EXISTS task_comments_insert_authorized ON public.task_comments;
CREATE POLICY task_comments_insert_authorized ON public.task_comments FOR INSERT TO authenticated
WITH CHECK(
    user_id=auth.uid() AND EXISTS(
        SELECT 1 FROM public.tasks task
        WHERE task.id=task_id AND (
            (task.task_list_id IS NULL AND public.can_view_task(task.id,auth.uid()))
            OR (task.task_list_id IS NOT NULL AND public.can_manage_task(task.id,auth.uid()))
        )
    )
);

DO $$ DECLARE item RECORD; BEGIN
    IF to_regclass('public.task_attachments') IS NOT NULL THEN
        FOR item IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='task_attachments'
        LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.task_attachments',item.policyname); END LOOP;
        EXECUTE 'ALTER TABLE public.task_attachments ENABLE ROW LEVEL SECURITY';
        EXECUTE 'CREATE POLICY task_attachments_view_task ON public.task_attachments FOR SELECT TO authenticated USING(public.can_view_task(task_id,auth.uid()))';
        EXECUTE 'CREATE POLICY task_attachments_manage_task ON public.task_attachments FOR INSERT TO authenticated WITH CHECK(user_id=auth.uid() AND public.can_manage_task(task_id,auth.uid()))';
        EXECUTE 'CREATE POLICY task_attachments_delete_own ON public.task_attachments FOR DELETE TO authenticated USING(user_id=auth.uid() AND public.can_manage_task(task_id,auth.uid()))';
    END IF;
END $$;

REVOKE ALL ON FUNCTION public.can_view_task_list(UUID,UUID),public.can_manage_task_list(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_task_list(UUID,UUID),public.can_manage_task_list(UUID,UUID) TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.task_lists TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
