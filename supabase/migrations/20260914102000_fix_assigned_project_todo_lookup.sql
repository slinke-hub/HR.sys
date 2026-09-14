-- Make the employee project To-Do deep link resilient to the live projects
-- table's text column types while retaining least-privilege output.
BEGIN;

CREATE OR REPLACE FUNCTION public.fetch_assigned_project_todo_context(
    p_project_id UUID,
    p_todo_id UUID DEFAULT NULL
)
RETURNS TABLE (
    project_id UUID,
    project_name TEXT,
    todo_id UUID,
    todo_title TEXT,
    due_at TIMESTAMPTZ,
    status TEXT
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT
        project.id::UUID AS project_id,
        COALESCE(NULLIF(BTRIM(project.project_name::TEXT), ''), 'Project')::TEXT AS project_name,
        assigned_todo.id::UUID AS todo_id,
        assigned_todo.title::TEXT AS todo_title,
        assigned_todo.due_at::TIMESTAMPTZ AS due_at,
        assigned_todo.status::TEXT AS status
    FROM public.project_todos assigned_todo
    JOIN public.projects project ON project.id = assigned_todo.project_id
    WHERE auth.uid() IS NOT NULL
      AND assigned_todo.project_id = p_project_id
      AND auth.uid() = ANY(COALESCE(assigned_todo.assignee_ids, ARRAY[]::UUID[]))
      AND (
          p_todo_id IS NULL
          OR EXISTS (
              SELECT 1
              FROM public.project_todos requested_todo
              WHERE requested_todo.id = p_todo_id
                AND requested_todo.project_id = p_project_id
                AND auth.uid() = ANY(COALESCE(requested_todo.assignee_ids, ARRAY[]::UUID[]))
          )
      )
    ORDER BY (assigned_todo.status::TEXT = 'DONE'), assigned_todo.due_at, assigned_todo.created_at;
$$;

REVOKE ALL ON FUNCTION public.fetch_assigned_project_todo_context(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_assigned_project_todo_context(UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
