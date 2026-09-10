-- Project-scoped To Do assignments, independent from the Tasks Manager.
BEGIN;

CREATE TABLE IF NOT EXISTS public.project_todos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (CHAR_LENGTH(BTRIM(title)) BETWEEN 1 AND 500),
    assignee_ids UUID[] NOT NULL CHECK (CARDINALITY(assignee_ids) > 0),
    due_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'TODO' CHECK (status IN ('TODO', 'DONE')),
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS project_todos_project_due_idx
    ON public.project_todos(project_id, status, due_at);
CREATE INDEX IF NOT EXISTS project_todos_assignees_idx
    ON public.project_todos USING GIN(assignee_ids);

CREATE OR REPLACE FUNCTION public.can_manage_project_todos(
    p_project_id UUID,
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
        FROM public.projects project
        JOIN public.profiles profile ON profile.id = p_user_id
        WHERE project.id = p_project_id
          AND profile.is_active IS DISTINCT FROM FALSE
          AND (
              project.created_by = p_user_id
              OR project.project_manager_id = p_user_id
              OR UPPER(BTRIM(COALESCE(profile.role, ''))) IN
                 ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) IN
                 ('GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER')
              OR (
                  (
                      UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) = 'OPERATIONS MANAGER'
                      OR BTRIM(COALESCE(profile.job_title_ar, '')) = 'مدير العمليات'
                  )
                  AND public.can_access_project(p_project_id, p_user_id)
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.is_project_todo_assignee_eligible(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        JOIN public.departments department ON department.id = profile.department_id
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM FALSE
          AND (COALESCE(department.name, '') || ' ' || COALESCE(department.name_ar, ''))
              ~* '(marketing|sales|operations?|التسويق|المبيعات|العمليات)'
    );
$$;

CREATE OR REPLACE FUNCTION public.add_project_todo(
    p_project_id UUID,
    p_title TEXT,
    p_assignee_ids UUID[],
    p_due_at TIMESTAMPTZ
)
RETURNS public.project_todos
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    project_row public.projects%ROWTYPE;
    todo_row public.project_todos%ROWTYPE;
    normalized_assignee_ids UUID[];
    invalid_assignee_id UUID;
BEGIN
    IF NOT public.can_manage_project_todos(p_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Only the project or Operations manager can assign project To Do items';
    END IF;
    IF NULLIF(BTRIM(p_title), '') IS NULL THEN
        RAISE EXCEPTION 'To Do title is required';
    END IF;
    IF p_due_at IS NULL THEN
        RAISE EXCEPTION 'To Do due date and time are required';
    END IF;

    SELECT * INTO project_row FROM public.projects WHERE id = p_project_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found'; END IF;
    SELECT ARRAY_AGG(DISTINCT assignee_id)
    INTO normalized_assignee_ids
    FROM UNNEST(COALESCE(p_assignee_ids, ARRAY[]::UUID[])) assignee_id
    WHERE assignee_id IS NOT NULL;
    IF COALESCE(CARDINALITY(normalized_assignee_ids), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one assignee';
    END IF;
    SELECT assignee_id INTO invalid_assignee_id
    FROM UNNEST(normalized_assignee_ids) assignee_id
    WHERE NOT public.is_project_todo_assignee_eligible(assignee_id)
    LIMIT 1;
    IF invalid_assignee_id IS NOT NULL THEN
        RAISE EXCEPTION 'Every assignee must be an active Marketing, Sales, or Operations employee';
    END IF;

    INSERT INTO public.project_todos(project_id, title, assignee_ids, due_at, created_by)
    VALUES (p_project_id, BTRIM(p_title), normalized_assignee_ids, p_due_at, auth.uid())
    RETURNING * INTO todo_row;

    UPDATE public.projects SET updated_at = NOW() WHERE id = p_project_id;
    RETURN todo_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_project_todo_completed(
    p_todo_id UUID,
    p_completed BOOLEAN
)
RETURNS public.project_todos
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    todo_row public.project_todos%ROWTYPE;
BEGIN
    SELECT * INTO todo_row FROM public.project_todos WHERE id = p_todo_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project To Do item not found'; END IF;
    IF NOT (auth.uid() = ANY(COALESCE(todo_row.assignee_ids, ARRAY[]::UUID[])))
       AND NOT public.can_manage_project_todos(todo_row.project_id, auth.uid()) THEN
        RAISE EXCEPTION 'You cannot complete this project To Do item';
    END IF;

    UPDATE public.project_todos
    SET status = CASE WHEN p_completed THEN 'DONE' ELSE 'TODO' END,
        completed_by = CASE WHEN p_completed THEN auth.uid() ELSE NULL END,
        completed_at = CASE WHEN p_completed THEN NOW() ELSE NULL END,
        updated_at = NOW()
    WHERE id = p_todo_id
    RETURNING * INTO todo_row;

    UPDATE public.projects SET updated_at = NOW() WHERE id = todo_row.project_id;
    RETURN todo_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_project_todo(p_todo_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    todo_row public.project_todos%ROWTYPE;
BEGIN
    SELECT * INTO todo_row FROM public.project_todos WHERE id = p_todo_id;
    IF NOT FOUND THEN RETURN FALSE; END IF;
    IF NOT public.can_manage_project_todos(todo_row.project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Only the project or Operations manager can delete project To Do items';
    END IF;
    DELETE FROM public.project_todos WHERE id = p_todo_id;
    UPDATE public.projects SET updated_at = NOW() WHERE id = todo_row.project_id;
    RETURN TRUE;
END;
$$;

ALTER TABLE public.project_todos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS project_todos_select ON public.project_todos;
CREATE POLICY project_todos_select ON public.project_todos
FOR SELECT TO authenticated
USING (public.can_access_project(project_id, auth.uid()));

REVOKE ALL ON public.project_todos FROM PUBLIC, authenticated;
GRANT SELECT ON public.project_todos TO authenticated;
REVOKE ALL ON FUNCTION public.can_manage_project_todos(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_project_todo_assignee_eligible(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_project_todo(UUID, TEXT, UUID[], TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_project_todo_completed(UUID, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_project_todo(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_manage_project_todos(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_project_todo_assignee_eligible(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_project_todo(UUID, TEXT, UUID[], TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_project_todo_completed(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_project_todo(UUID) TO authenticated;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.project_todos;
EXCEPTION WHEN duplicate_object OR undefined_object THEN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
