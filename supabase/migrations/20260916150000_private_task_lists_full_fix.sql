-- Allow truly private task lists (department_id = NULL).
-- Previously, the validate_task_list_department_visibility trigger would always
-- coalesce NULL department_id to the owner's own department, making it impossible
-- to create a list that is invisible to all colleagues.
--
-- This migration:
--  1. Updates the validate_task_list_department_visibility trigger so that
--     department_id = NULL is preserved as-is (private list).
--  2. Updates the validate_task_list_department_access trigger to also allow NULL.
--  3. Updates can_view_task_list so that private lists (department_id IS NULL,
--     visible_to_all = false) are only visible to the owner.
--  4. Updates the create_task_list_for_user RPC to honour NULL department_id.

BEGIN;

-- ─── 1. Fix the visibility trigger ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_task_list_department_visibility()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  owner_department uuid;
  actor_is_admin   boolean := false;
  invalid_viewer   uuid;
BEGIN
  SELECT department_id INTO owner_department
    FROM public.profiles
   WHERE id = NEW.owner_id;

  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = auth.uid()
       AND upper(coalesce(p.role, '')) IN ('ADMIN', 'OWNER', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
  ) INTO actor_is_admin;

  -- Only admins can set visible_to_all = true
  IF NEW.visible_to_all AND NOT actor_is_admin THEN
    RAISE EXCEPTION 'Only administrators can make a task list visible to all departments'
      USING ERRCODE = '42501';
  END IF;

  -- When visible_to_all, clear the department_id
  IF NEW.visible_to_all THEN
    NEW.department_id := NULL;
  END IF;
  -- NOTE: if department_id IS NULL and visible_to_all is false → private list.
  --       We intentionally do NOT coalesce to the owner's department here.

  -- Non-admins cannot assign a list to a department other than their own
  IF NOT actor_is_admin
     AND NOT NEW.visible_to_all
     AND NEW.department_id IS NOT NULL
     AND NEW.department_id IS DISTINCT FROM owner_department THEN
    RAISE EXCEPTION 'Employees can only create task lists for their own department'
      USING ERRCODE = '42501';
  END IF;

  -- Remove owner from shared_with
  NEW.shared_with := array_remove(coalesce(NEW.shared_with, '{}'::uuid[]), NEW.owner_id);

  -- When a specific department is set, all shared_with members must belong to it
  IF NEW.department_id IS NOT NULL THEN
    SELECT viewer_id INTO invalid_viewer
      FROM unnest(NEW.shared_with) viewer_id
      LEFT JOIN public.profiles viewer ON viewer.id = viewer_id
     WHERE viewer.id IS NULL
        OR (NOT NEW.visible_to_all AND viewer.department_id IS DISTINCT FROM NEW.department_id)
     LIMIT 1;

    IF invalid_viewer IS NOT NULL THEN
      RAISE EXCEPTION 'A task list can only be shared with employees in its department'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ─── 2. Fix the access trigger ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_task_list_department_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  owner_department uuid;
  caller_role      text;
  invalid_member   uuid;
BEGIN
  SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
  SELECT department_id INTO owner_department FROM public.profiles WHERE id = NEW.owner_id;

  -- Non-admins trying to set a *different* department → force their own
  IF NEW.department_id IS NOT NULL AND NEW.department_id IS DISTINCT FROM owner_department THEN
    IF UPPER(COALESCE(caller_role, '')) NOT IN ('ADMIN','OWNER','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN') THEN
      NEW.department_id := owner_department;
    END IF;
  END IF;
  -- NULL department_id is intentional (private list) — leave it alone.

  NEW.visible_to_all := false;
  NEW.shared_with    := array_remove(COALESCE(NEW.shared_with,    '{}'::uuid[]), NEW.owner_id);
  NEW.can_add_users  := array_remove(COALESCE(NEW.can_add_users,  '{}'::uuid[]), NEW.owner_id);
  NEW.can_delete_users := array_remove(COALESCE(NEW.can_delete_users, '{}'::uuid[]), NEW.owner_id);

  IF NEW.department_id IS NOT NULL THEN
    SELECT member_id INTO invalid_member
      FROM unnest(NEW.shared_with || NEW.can_add_users || NEW.can_delete_users) AS member_id
      LEFT JOIN public.profiles member ON member.id = member_id
     WHERE member.id IS NULL OR member.department_id IS DISTINCT FROM NEW.department_id
     LIMIT 1;

    IF invalid_member IS NOT NULL THEN
      RAISE EXCEPTION 'Task-list access can only be granted to employees in the selected department'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ─── 3. Fix can_view_task_list ───────────────────────────────────────────────
-- Private list (department_id IS NULL, visible_to_all = false):
--   → only the owner can see it (shared_with members can also be granted access)
CREATE OR REPLACE FUNCTION public.can_view_task_list(
  p_list_id uuid,
  p_user_id uuid DEFAULT auth.uid()
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.task_lists list
      JOIN public.profiles  viewer ON viewer.id = p_user_id
     WHERE list.id = p_list_id
       AND (
         -- Owner always has access
         list.owner_id = p_user_id
         -- Explicitly shared with this user
         OR p_user_id = ANY(COALESCE(list.shared_with, '{}'::uuid[]))
         -- Visible to all departments (admins set this)
         OR list.visible_to_all
         -- Department-scoped list: viewer is in the same department
         OR (
           list.department_id IS NOT NULL
           AND viewer.department_id = list.department_id
         )
         -- Admins can see department-scoped lists but NOT private lists
         -- (private = department_id IS NULL AND visible_to_all = false)
         -- unless they are the owner or explicitly shared.
       )
  );
$$;

-- ─── 4. Fix create_task_list_for_user RPC ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_task_list_for_user(
  p_name            text,
  p_shared_with     uuid[]  DEFAULT '{}'::uuid[],
  p_department_id   uuid    DEFAULT NULL,
  p_visible_to_all  boolean DEFAULT false,
  p_can_add_users   uuid[]  DEFAULT '{}'::uuid[],
  p_can_delete_users uuid[] DEFAULT '{}'::uuid[],
  p_description     text    DEFAULT NULL,
  p_template        text    DEFAULT 'none',
  p_notify_assignee boolean DEFAULT false,
  p_notify_complete boolean DEFAULT false
)
RETURNS public.task_lists
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  caller_id        uuid := auth.uid();
  caller_role      text;
  own_department   uuid;
  target_department uuid;
  result_row       public.task_lists;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT role, department_id INTO caller_role, own_department
    FROM public.profiles WHERE id = caller_id;

  -- NULL p_department_id means "private list" — preserve it.
  target_department := p_department_id;

  -- Non-admins cannot pick another department
  IF target_department IS NOT NULL AND target_department IS DISTINCT FROM own_department THEN
    IF UPPER(COALESCE(caller_role, '')) NOT IN ('ADMIN','OWNER','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN') THEN
      target_department := own_department;
    END IF;
  END IF;

  -- When a department is set, all shared members must belong to it
  IF target_department IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
        FROM unnest(
               COALESCE(p_shared_with,      '{}'::uuid[])
            || COALESCE(p_can_add_users,    '{}'::uuid[])
            || COALESCE(p_can_delete_users, '{}'::uuid[])
             ) member_id
        LEFT JOIN public.profiles member ON member.id = member_id
       WHERE member.id IS NULL OR member.department_id IS DISTINCT FROM target_department
    ) THEN
      RAISE EXCEPTION 'Task-list access can only be granted to employees in the selected department'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  INSERT INTO public.task_lists(
    name, owner_id, shared_with, department_id, visible_to_all,
    can_add_users, can_delete_users, description, template,
    notify_assignee, notify_complete
  )
  VALUES (
    trim(p_name), caller_id,
    COALESCE(p_shared_with,      '{}'::uuid[]),
    target_department,
    false,
    COALESCE(p_can_add_users,    '{}'::uuid[]),
    COALESCE(p_can_delete_users, '{}'::uuid[]),
    p_description,
    COALESCE(p_template, 'none'),
    COALESCE(p_notify_assignee, false),
    COALESCE(p_notify_complete, false)
  )
  RETURNING * INTO result_row;

  RETURN result_row;
END;
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
