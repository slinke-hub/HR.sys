--
-- PostgreSQL database dump
--

\restrict 7GtYyiaEQtO4ufGqWWb2lCra7cpDqp7zjJx2XCier5JGbWqoXC71XzIl9qSwzEz

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: project_todos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_todos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    title text NOT NULL,
    assignee_ids uuid[] NOT NULL,
    due_at timestamp with time zone NOT NULL,
    status text DEFAULT 'TODO'::text NOT NULL,
    created_by uuid NOT NULL,
    completed_by uuid,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT project_todos_assignee_ids_check CHECK ((cardinality(assignee_ids) > 0)),
    CONSTRAINT project_todos_status_check CHECK ((status = ANY (ARRAY['TODO'::text, 'DONE'::text]))),
    CONSTRAINT project_todos_title_check CHECK (((char_length(btrim(title)) >= 1) AND (char_length(btrim(title)) <= 500)))
);


--
-- Name: add_project_todo(uuid, text, uuid[], timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_project_todo(p_project_id uuid, p_title text, p_assignee_ids uuid[], p_due_at timestamp with time zone) RETURNS public.project_todos
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: task_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_comments (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    task_id uuid NOT NULL,
    user_id uuid NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    parent_comment_id uuid,
    edited_at timestamp with time zone,
    attachments jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT task_comments_attachments_array_check CHECK ((jsonb_typeof(attachments) = 'array'::text))
);


--
-- Name: COLUMN task_comments.attachments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.task_comments.attachments IS 'Private task-attachments storage references with file name, MIME type, and size metadata.';


--
-- Name: add_task_comment(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_task_comment(p_task_id uuid, p_content text, p_attachments jsonb DEFAULT '[]'::jsonb) RETURNS public.task_comments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
$_$;


--
-- Name: job_titles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_titles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    department_id uuid NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name_ar text,
    job_level text
);


--
-- Name: admin_add_department_job_title(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_add_department_job_title(p_department_id uuid, p_name text) RETURNS public.job_titles
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    clean_name TEXT := NULLIF(BTRIM(COALESCE(p_name, '')), '');
    existing_title public.job_titles%ROWTYPE;
    saved_title public.job_titles%ROWTYPE;
BEGIN
    IF NOT public.is_system_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only an administrator can add department job titles' USING ERRCODE = '42501';
    END IF;
    IF clean_name IS NULL THEN RAISE EXCEPTION 'Job title is required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.departments WHERE id = p_department_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Select an active department';
    END IF;

    SELECT * INTO existing_title
    FROM public.job_titles
    WHERE department_id = p_department_id AND LOWER(name) = LOWER(clean_name)
    ORDER BY created_at
    LIMIT 1;

    IF FOUND THEN
        UPDATE public.job_titles SET name = clean_name, is_active = TRUE
        WHERE id = existing_title.id RETURNING * INTO saved_title;
    ELSE
        INSERT INTO public.job_titles(department_id, name, is_active)
        VALUES (p_department_id, clean_name, TRUE)
        RETURNING * INTO saved_title;
    END IF;
    RETURN saved_title;
END;
$$;


--
-- Name: admin_can_read_all_profiles(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_can_read_all_profiles() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND UPPER(COALESCE(role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
  );
$$;


--
-- Name: admin_delete_employee_request(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_delete_employee_request(p_source_table text, p_source_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
    source_row JSONB;
    source_owner UUID;
    source_status TEXT;
    workflow_status TEXT;
    actor_is_admin BOOLEAN := FALSE;
    owner_can_withdraw BOOLEAN := FALSE;
    deleted_count INTEGER := 0;
BEGIN
    IF p_source_table NOT IN ('requests', 'leave_requests', 'document_requests', 'expenses') THEN
        RAISE EXCEPTION 'Unsupported employee request type';
    END IF;

    EXECUTE format(
        'SELECT to_jsonb(request_row) FROM public.%I request_row WHERE id = $1',
        p_source_table
    ) INTO source_row USING p_source_id;

    IF source_row IS NULL THEN
        RAISE EXCEPTION 'Employee request not found';
    END IF;

    source_owner := NULLIF(source_row->>'employee_id', '')::UUID;
    source_status := UPPER(COALESCE(source_row->>'status', 'PENDING'));

    SELECT workflow.status
      INTO workflow_status
      FROM public.request_approval_workflows workflow
     WHERE workflow.source_table = p_source_table
       AND workflow.source_id = p_source_id
     ORDER BY workflow.created_at DESC
     LIMIT 1;

    actor_is_admin := public.is_employee_request_admin(auth.uid());
    owner_can_withdraw := source_owner = auth.uid()
        AND COALESCE(NULLIF(source_row->>'is_archived', '')::BOOLEAN, FALSE) IS FALSE
        AND source_status LIKE 'PENDING%'
        AND COALESCE(UPPER(workflow_status), 'PENDING') = 'PENDING';

    IF NOT actor_is_admin AND NOT owner_can_withdraw THEN
        RAISE EXCEPTION 'Only administrators, or the request owner before final approval, can delete this request'
            USING ERRCODE = '42501';
    END IF;

    DELETE FROM public.request_approval_workflows
    WHERE source_table = p_source_table AND source_id = p_source_id;

    DELETE FROM public.notifications
    WHERE metadata->>'source_table' = p_source_table
      AND metadata->>'source_id' = p_source_id::TEXT;

    EXECUTE format('DELETE FROM public.%I WHERE id = $1', p_source_table) USING p_source_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    IF deleted_count = 0 THEN RAISE EXCEPTION 'Employee request not found'; END IF;

    RETURN jsonb_build_object(
        'deleted', TRUE,
        'withdrawn_by_owner', owner_can_withdraw AND NOT actor_is_admin,
        'source_table', p_source_table,
        'source_id', p_source_id
    );
END;
$_$;


--
-- Name: admin_get_user_email(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_get_user_email(target_user_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'pg_temp'
    AS $$
DECLARE
    result_email TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'ADMIN'
    ) THEN
        RAISE EXCEPTION 'Only an administrator can view login emails' USING ERRCODE = '42501';
    END IF;

    SELECT LOWER(BTRIM(email)) INTO result_email
    FROM auth.users
    WHERE id = target_user_id;

    IF result_email IS NULL THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;
    RETURN result_email;
END;
$$;


--
-- Name: admin_list_user_lock_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_list_user_lock_status() RETURNS TABLE(user_id uuid, email text, attempts integer, locked_until timestamp with time zone, is_locked boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'pg_temp'
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Only an administrator can view account lock status' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT users.id,
           LOWER(users.email),
           COALESCE(attempts.attempts, 0),
           attempts.locked_until,
           COALESCE(attempts.locked_until > NOW(), FALSE)
    FROM auth.users AS users
    LEFT JOIN public.login_attempts AS attempts ON attempts.email = LOWER(users.email)
    ORDER BY users.email;
END;
$$;


--
-- Name: admin_save_translation_bundle(jsonb, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_save_translation_bundle(p_ui_translations jsonb DEFAULT '[]'::jsonb, p_department_translations jsonb DEFAULT '[]'::jsonb, p_profile_translations jsonb DEFAULT '[]'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    item JSONB;
    ui_count INTEGER := 0;
    department_count INTEGER := 0;
    profile_count INTEGER := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN'
    ) THEN
        RAISE EXCEPTION 'Only an administrator can save system translations' USING ERRCODE = '42501';
    END IF;

    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(p_ui_translations, '[]'::JSONB)) LOOP
        IF NULLIF(BTRIM(item->>'trans_key'), '') IS NULL THEN
            RAISE EXCEPTION 'Translation key cannot be empty' USING ERRCODE = '22023';
        END IF;
        INSERT INTO public.system_translations (trans_key, trans_en, trans_ar, updated_at)
        VALUES (item->>'trans_key', COALESCE(item->>'trans_en', ''), COALESCE(item->>'trans_ar', ''), NOW())
        ON CONFLICT (trans_key) DO UPDATE
        SET trans_en = EXCLUDED.trans_en,
            trans_ar = EXCLUDED.trans_ar,
            updated_at = NOW();
        ui_count := ui_count + 1;
    END LOOP;

    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(p_department_translations, '[]'::JSONB)) LOOP
        UPDATE public.departments
        SET name_ar = NULLIF(BTRIM(item->>'name_ar'), '')
        WHERE id = (item->>'department_id')::UUID;
        IF FOUND THEN department_count := department_count + 1; END IF;
    END LOOP;

    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(p_profile_translations, '[]'::JSONB)) LOOP
        UPDATE public.profiles
        SET display_name_ar = NULLIF(BTRIM(item->>'display_name_ar'), ''),
            job_title_ar = NULLIF(BTRIM(item->>'job_title_ar'), '')
        WHERE id = (item->>'profile_id')::UUID;
        IF FOUND THEN profile_count := profile_count + 1; END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'ui_translations_saved', ui_count,
        'departments_saved', department_count,
        'profiles_saved', profile_count
    );
END;
$$;


--
-- Name: admin_set_user_lock(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_set_user_lock(target_user_id uuid, should_lock boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'pg_temp'
    AS $$
DECLARE
    target_email TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Only an administrator can lock or unlock users' USING ERRCODE = '42501';
    END IF;
    IF target_user_id = auth.uid() AND should_lock THEN
        RAISE EXCEPTION 'Administrators cannot lock their own account' USING ERRCODE = '22023';
    END IF;

    SELECT LOWER(email) INTO target_email FROM auth.users WHERE id = target_user_id;
    IF target_email IS NULL THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO public.login_attempts (email, attempts, locked_until)
    VALUES (target_email, CASE WHEN should_lock THEN 3 ELSE 0 END,
            CASE WHEN should_lock THEN NOW() + INTERVAL '100 years' ELSE NULL END)
    ON CONFLICT (email) DO UPDATE
    SET attempts = EXCLUDED.attempts,
        locked_until = EXCLUDED.locked_until;
END;
$$;


--
-- Name: admin_update_job_title_translation(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_update_job_title_translation(p_job_title_id uuid, p_name_ar text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id=auth.uid()
          AND upper(COALESCE(profile.role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
    ) THEN
        RAISE EXCEPTION 'Only administrators can edit job-title translations' USING ERRCODE='42501';
    END IF;
    UPDATE public.job_titles SET name_ar=NULLIF(btrim(p_name_ar),'') WHERE id=p_job_title_id;
    RETURN FOUND;
END;
$$;


--
-- Name: admin_update_user_credentials(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_update_user_credentials(target_user_id uuid, new_email text, new_password text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions', 'pg_temp'
    AS $_$
DECLARE
    normalized_email TEXT := LOWER(BTRIM(new_email));
    previous_email TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'ADMIN'
    ) THEN
        RAISE EXCEPTION 'Only an administrator can update login credentials' USING ERRCODE = '42501';
    END IF;
    IF normalized_email IS NULL OR normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'Enter a valid email address' USING ERRCODE = '22023';
    END IF;
    IF new_password IS NOT NULL AND LENGTH(new_password) < 8 THEN
        RAISE EXCEPTION 'Password must contain at least 8 characters' USING ERRCODE = '22023';
    END IF;

    SELECT LOWER(BTRIM(email)) INTO previous_email FROM auth.users WHERE id = target_user_id FOR UPDATE;
    IF previous_email IS NULL THEN
        RAISE EXCEPTION 'User account was not found' USING ERRCODE = 'P0002';
    END IF;
    IF EXISTS (SELECT 1 FROM auth.users WHERE LOWER(email) = normalized_email AND id <> target_user_id) THEN
        RAISE EXCEPTION 'Another user already uses this email address' USING ERRCODE = '23505';
    END IF;

    UPDATE auth.users
    SET email = normalized_email,
        email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
        encrypted_password = CASE
            WHEN new_password IS NULL THEN encrypted_password
            ELSE crypt(new_password, gen_salt('bf'))
        END,
        updated_at = NOW()
    WHERE id = target_user_id;

    UPDATE auth.identities
    SET identity_data = COALESCE(identity_data, '{}'::JSONB)
        || JSONB_BUILD_OBJECT('email', normalized_email),
        updated_at = NOW()
    WHERE user_id = target_user_id AND provider = 'email';

    IF previous_email <> normalized_email THEN
        UPDATE public.login_attempts SET email = normalized_email WHERE LOWER(email) = previous_email;
    END IF;
    RETURN TRUE;
END;
$_$;


--
-- Name: apply_task_creation_defaults(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_task_creation_defaults() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    department_manager_id uuid;
BEGIN
    IF NEW.assignee_id IS NULL THEN
        NEW.assignee_id := NEW.created_by;
    END IF;

    IF NEW.supervisor_id IS NULL AND NULLIF(BTRIM(NEW.department), '') IS NOT NULL THEN
        SELECT COALESCE(
            department.head_id,
            NULLIF(to_jsonb(department)->>'manager_id', '')::uuid
        )
        INTO department_manager_id
        FROM public.departments AS department
        WHERE department.id::text = NEW.department
           OR department.name = NEW.department
           OR COALESCE(to_jsonb(department)->>'name_ar', '') = NEW.department
        ORDER BY CASE WHEN department.name = NEW.department THEN 0 ELSE 1 END
        LIMIT 1;

        NEW.supervisor_id := department_manager_id;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION apply_task_creation_defaults(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.apply_task_creation_defaults() IS 'Defaults an unassigned task to its creator and resolves an unset supervisor from the selected department manager.';


--
-- Name: archive_and_delete_employee(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_and_delete_employee(target_user_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $_$
DECLARE
    target_profile public.profiles%ROWTYPE;
    target_email TEXT;
    archived_count INTEGER := 0;
    ref RECORD;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND UPPER(COALESCE(role, '')) = 'ADMIN') THEN
        RETURN jsonb_build_object('success', FALSE, 'error_message', 'Only an administrator can delete an employee');
    END IF;
    IF target_user_id = auth.uid() THEN
        RETURN jsonb_build_object('success', FALSE, 'error_message', 'Administrators cannot delete their own signed-in account');
    END IF;

    SELECT * INTO target_profile FROM public.profiles WHERE id = target_user_id FOR UPDATE;
    IF NOT FOUND THEN 
        RETURN jsonb_build_object('success', FALSE, 'error_message', 'Employee not found');
    END IF;
    SELECT email INTO target_email FROM auth.users WHERE id = target_user_id;

    UPDATE public.contracts SET
        is_archived = TRUE, archived_at = NOW(), archived_by = auth.uid(),
        former_employee_name = COALESCE(former_employee_name, target_profile.full_name),
        former_employee_email = COALESCE(former_employee_email, target_email),
        former_employee_number = COALESCE(former_employee_number, target_profile.emp_index::TEXT),
        employee_id = NULL, updated_at = NOW()
    WHERE employee_id = target_user_id;
    GET DIAGNOSTICS archived_count = ROW_COUNT;

    -- STEP 0: Explicitly clear known nullable foreign keys that could cause cyclic constraint violations
    UPDATE public.departments SET head_id = NULL WHERE head_id = target_user_id;
    
    BEGIN
        UPDATE public.profiles SET supervisor_id = NULL WHERE supervisor_id = target_user_id;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- STEP 1: Delete specific explicit references that we know about
    FOR ref IN
        SELECT DISTINCT cols.table_schema, cols.table_name, cols.column_name
        FROM information_schema.columns cols
        JOIN information_schema.tables tbl
          ON tbl.table_schema = cols.table_schema AND tbl.table_name = cols.table_name
        WHERE cols.table_schema = 'public' AND tbl.table_type = 'BASE TABLE'
          AND cols.table_name NOT IN ('profiles', 'contracts')
          AND cols.column_name IN ('employee_id','user_id','created_by','admin_id','sender_id','receiver_id','assignee_id','approver_id','actor_id','actor_user_id','target_user_id','assigned_to','owner_id')
          AND cols.data_type = 'uuid'
    LOOP
        EXECUTE format('DELETE FROM %I.%I WHERE %I = $1', ref.table_schema, ref.table_name, ref.column_name) USING target_user_id;
    END LOOP;

    -- STEP 2: Clear remaining foreign key references generically
    FOR ref IN
        SELECT ns.nspname table_schema, rel.relname table_name, att.attname column_name, att.attnotnull is_required
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = rel.relnamespace
        JOIN pg_class parent_rel ON parent_rel.oid = con.confrelid
        JOIN pg_namespace parent_ns ON parent_ns.oid = parent_rel.relnamespace
        JOIN unnest(con.conkey) AS key(attnum) ON TRUE
        JOIN pg_attribute att ON att.attrelid = rel.oid AND att.attnum = key.attnum
        WHERE con.contype = 'f' AND ns.nspname = 'public'
          AND NOT (rel.relname = 'contracts' AND att.attname = 'employee_id')
          AND ((parent_ns.nspname = 'public' AND parent_rel.relname = 'profiles')
            OR (parent_ns.nspname = 'auth' AND parent_rel.relname = 'users'))
    LOOP
        IF ref.is_required THEN
            EXECUTE format('DELETE FROM %I.%I WHERE %I = $1', ref.table_schema, ref.table_name, ref.column_name) USING target_user_id;
        ELSE
            EXECUTE format('UPDATE %I.%I SET %I = NULL WHERE %I = $1', ref.table_schema, ref.table_name, ref.column_name, ref.column_name) USING target_user_id;
        END IF;
    END LOOP;

    -- STEP 3: Ensure external schemas (like Supabase storage) don't have RESTRICT constraints
    BEGIN
        UPDATE storage.objects SET owner = NULL WHERE owner = target_user_id;
    EXCEPTION
        WHEN OTHERS THEN
            -- Ignore if storage schema doesn't exist or isn't accessible
    END;

    -- Finally, delete the profile and auth user
    DELETE FROM public.profiles WHERE id = target_user_id;
    DELETE FROM auth.users WHERE id = target_user_id;
    RETURN jsonb_build_object('success', TRUE, 'archived_contracts', archived_count);

EXCEPTION
    WHEN OTHERS THEN
        -- Return a JSON error payload instead of throwing an exception (which translates to HTTP 409 or 400)
        RETURN jsonb_build_object(
            'success', FALSE, 
            'error_message', SQLERRM, 
            'error_detail', SQLSTATE
        );
END; $_$;


--
-- Name: archive_completed_tasks(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_completed_tasks() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    archived_count integer;
BEGIN
    UPDATE public.tasks
       SET archived_at = now()
     WHERE archived_at IS NULL
       AND lower(btrim(coalesce(status, ''))) IN ('completed', 'approved');

    GET DIAGNOSTICS archived_count = ROW_COUNT;
    RETURN archived_count;
END;
$$;


--
-- Name: archive_crm_deal_attachments(uuid, text[], uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_crm_deal_attachments(p_deal_id uuid, p_categories text[], p_keep_ids uuid[] DEFAULT ARRAY[]::uuid[]) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: archive_ended_employment_contract(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_ended_employment_contract() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF LOWER(BTRIM(COALESCE(NEW.status, ''))) IN ('terminated', 'resigned') THEN
        NEW.is_archived := TRUE;
        NEW.archived_at := COALESCE(NEW.archived_at, NOW());
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: archive_task_attachments(uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_task_attachments(p_task_id uuid, p_keep_ids uuid[] DEFAULT ARRAY[]::uuid[]) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: assign_profile_employee_number(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_profile_employee_number() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    sequence_value BIGINT;
BEGIN
    -- Serialize automatic and explicitly imported employee numbers so the
    -- sequence never falls behind an imported value.
    PERFORM pg_advisory_xact_lock(hashtext('profiles_emp_index_assignment'));

    IF NEW.emp_index IS NULL THEN
        NEW.emp_index := nextval('public.profiles_emp_index_seq');
    ELSE
        SELECT last_value INTO sequence_value FROM public.profiles_emp_index_seq;
        IF NEW.emp_index > sequence_value THEN
            PERFORM setval('public.profiles_emp_index_seq', NEW.emp_index, TRUE);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: assign_project_team(uuid, uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_project_team(p_project_id uuid, p_project_manager_id uuid, p_assignee_ids uuid[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_ids uuid[];
    v_invalid uuid;
    v_can_manage boolean := false;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_project FROM public.projects WHERE id = p_project_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE = 'P0002'; END IF;
    SELECT public.is_project_portfolio_admin(auth.uid())
        OR v_project.created_by = auth.uid()
        OR v_project.project_manager_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.profiles profile
             WHERE profile.id = auth.uid()
               AND profile.is_active IS DISTINCT FROM false
               AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) IN ('OPERATIONS MANAGER','OPERATION MANAGER','PROJECT MANAGER')
        ) INTO v_can_manage;
    IF NOT v_can_manage THEN RAISE EXCEPTION 'Only a project manager can assign the project team' USING ERRCODE = '42501'; END IF;

    SELECT ARRAY_AGG(DISTINCT value) INTO v_ids
      FROM UNNEST(COALESCE(p_assignee_ids, ARRAY[]::uuid[])) value
     WHERE value IS NOT NULL;
    SELECT value INTO v_invalid
      FROM UNNEST(COALESCE(v_ids, ARRAY[]::uuid[])) value
     WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile WHERE profile.id = value AND profile.is_active IS DISTINCT FROM false)
     LIMIT 1;
    IF v_invalid IS NOT NULL THEN RAISE EXCEPTION 'Every project assignee must be active' USING ERRCODE = '22023'; END IF;
    IF p_project_manager_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.profiles profile WHERE profile.id = p_project_manager_id AND profile.is_active IS DISTINCT FROM false
    ) THEN RAISE EXCEPTION 'Project manager must be an active employee' USING ERRCODE = '22023'; END IF;

    UPDATE public.projects
       SET project_manager_id = p_project_manager_id,
           assigned_people = COALESCE(v_ids, ARRAY[]::uuid[]),
           updated_at = NOW()
     WHERE id = p_project_id;
    RETURN jsonb_build_object('project_id', p_project_id, 'project_manager_id', p_project_manager_id,
                              'assigned_people', COALESCE(v_ids, ARRAY[]::uuid[]), 'actor_id', auth.uid());
END;
$$;


--
-- Name: assign_task(uuid, uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_task(p_task_id uuid, p_assignee_ids uuid[]) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_ids uuid[];
    v_invalid uuid;
    v_can_assign boolean := false;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = auth.uid()
          AND profile.is_active IS DISTINCT FROM false
          AND (
              profile.id IN (v_task.created_by, v_task.supervisor_id)
              OR UPPER(COALESCE(profile.role, '')) IN ('ADMIN','OWNER','ROLE SYSTEM ADMIN','SYSTEM ADMIN','CEO','GM','GENERAL MANAGER')
              OR UPPER(COALESCE(profile.job_title, '')) IN ('CEO','GM','GENERAL MANAGER')
              OR COALESCE(public.can_assign_tasks_company_wide(auth.uid()), false)
          )
    ) INTO v_can_assign;
    IF NOT v_can_assign THEN
        RAISE EXCEPTION 'You are not authorized to assign this task' USING ERRCODE = '42501';
    END IF;

    SELECT ARRAY_AGG(DISTINCT value) INTO v_ids
      FROM UNNEST(COALESCE(p_assignee_ids, ARRAY[]::uuid[])) value
     WHERE value IS NOT NULL;
    SELECT value INTO v_invalid
      FROM UNNEST(COALESCE(v_ids, ARRAY[]::uuid[])) value
     WHERE NOT EXISTS (
         SELECT 1 FROM public.profiles profile
          WHERE profile.id = value AND profile.is_active IS DISTINCT FROM false
     )
     LIMIT 1;
    IF v_invalid IS NOT NULL THEN
        RAISE EXCEPTION 'Every assignee must be an active employee' USING ERRCODE = '22023';
    END IF;

    UPDATE public.tasks
       SET assignee_ids = COALESCE(v_ids, ARRAY[]::uuid[]),
           assignee_id = (COALESCE(v_ids, ARRAY[]::uuid[]))[1]
     WHERE id = v_task.id;

    RETURN jsonb_build_object(
        'task_id', v_task.id,
        'assignee_ids', COALESCE(v_ids, ARRAY[]::uuid[]),
        'actor_id', auth.uid()
    );
END;
$$;


--
-- Name: can_access_crm(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_crm(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        LEFT JOIN public.departments department ON department.id = profile.department_id
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM false
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'CEO', 'GM', 'GENERAL MANAGER'
              )
              OR UPPER(COALESCE(profile.job_title, '')) ~ '(^|[^A-Z])(CEO|GM|GENERAL MANAGER|SALES|MARKETING)([^A-Z]|$)'
              OR COALESCE(profile.job_title, '') ~ '(المبيعات|التسويق)'
              OR COALESCE(department.name, '') ~* '(sales|marketing|المبيعات|التسويق)'
          )
    );
$_$;


--
-- Name: can_access_project(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_project(p_project_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.projects project
        WHERE project.id = p_project_id
          AND (
              project.created_by = p_user_id
              OR project.project_manager_id = p_user_id
              OR p_user_id = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
              OR public.is_project_portfolio_admin(p_user_id)
          )
    );
$$;


--
-- Name: can_access_task(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_access_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: can_add_task_to_list(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_add_task_to_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT public.can_assign_tasks_company_wide(p_user_id)
        OR EXISTS (
            SELECT 1
            FROM public.task_lists list
            JOIN public.profiles viewer ON viewer.id = p_user_id
            WHERE list.id = p_list_id
              AND (
                  list.owner_id = p_user_id
                  OR list.department_id = viewer.department_id
                  OR p_user_id = ANY(COALESCE(list.can_add_users, '{}'::UUID[]))
              )
        );
$$;


--
-- Name: can_assign_tasks_company_wide(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_assign_tasks_company_wide(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'
              )
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.job_title, ''), '[_-]+', ' ', 'g'))) IN (
                  'GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
              )
          )
    );
$$;


--
-- Name: can_delete_crm_deal(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_delete_crm_deal(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
$_$;


--
-- Name: can_delete_task(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_delete_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tasks task
    LEFT JOIN public.task_lists list ON list.id = task.task_list_id
    WHERE task.id = p_task_id
      AND (
        task.created_by = p_user_id
        OR public.is_task_admin(p_user_id)
        OR p_user_id = ANY(COALESCE(list.can_delete_users, '{}'::uuid[]))
      )
  );
$$;


--
-- Name: can_manage_attendance_records(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_attendance_records(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'
              )
              OR UPPER(BTRIM(COALESCE(viewer.job_title, ''))) IN (
                  'GM', 'GENERAL MANAGER', 'GENERAL MANAGER (GM)',
                  'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER', 'CHIEF EXECUTIVE OFFICER (CEO)'
              )
              OR BTRIM(COALESCE(viewer.job_title_ar, '')) IN ('المدير العام', 'الرئيس التنفيذي')
          )
    );
$$;


--
-- Name: can_manage_employee_contracts(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_employee_contracts(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = p_user_id
          AND is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(COALESCE(role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN')
              OR UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
          )
    );
$$;


--
-- Name: can_manage_employee_photos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_employee_photos(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_user_id
          AND is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(COALESCE(role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN')
              OR UPPER(COALESCE(job_title, '')) = 'HR MANAGER'
          )
    );
$$;


--
-- Name: can_manage_hr_suite_beta(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_hr_suite_beta(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role,''), '[_-]+', ' ', 'g'))) IN ('ADMIN','OWNER','ROLE SYSTEM ADMIN','SYSTEM ADMIN','HR MANAGER')
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.job_title,''), '[_-]+', ' ', 'g'))) IN ('HR MANAGER','FINANCE MANAGER','ACCOUNTANT MANAGER','GM','GENERAL MANAGER','CEO','CHIEF EXECUTIVE','CHIEF EXECUTIVE OFFICER')
              OR BTRIM(COALESCE(viewer.job_title_ar,'')) IN ('مدير الموارد البشرية','المدير المالي','مدير الحسابات','المدير العام','الرئيس التنفيذي')
          )
    );
$$;


--
-- Name: can_manage_project_todos(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_project_todos(p_project_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: can_manage_task(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: can_manage_task_attachments(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_task_attachments(p_task_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: can_manage_task_list(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manage_task_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (SELECT 1 FROM public.task_lists list WHERE list.id=p_list_id AND list.owner_id=p_user_id);
$$;


--
-- Name: can_marketing_manager_edit_task(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_marketing_manager_edit_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT public.is_marketing_task_manager(p_user_id)
       AND EXISTS (
           SELECT 1
           FROM public.tasks task
           WHERE task.id = p_task_id
             AND public.is_marketing_managed_task_list(task.task_list_id)
       );
$$;


--
-- Name: can_view_all_attendance(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_all_attendance(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'
              )
              OR public.is_executive_admin_title(viewer.job_title)
          )
    );
$$;


--
-- Name: can_view_business_financials(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_business_financials(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
$_$;


--
-- Name: can_view_company_employee_names(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_company_employee_names(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'
              )
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(viewer.job_title, ''), '[_-]+', ' ', 'g'))) IN (
                  'GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
              )
          )
    );
$$;


--
-- Name: can_view_employee_request(text, uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_employee_request(p_source_table text, p_source_id uuid, p_employee_id uuid, p_viewer_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT p_viewer_id=p_employee_id
    OR public.is_system_admin(p_viewer_id)
    OR public.is_department_manager_for(p_viewer_id,p_employee_id)
    OR public.is_request_workflow_approver(p_source_table,p_source_id,p_viewer_id);
$$;


--
-- Name: can_view_employees_radar(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_employees_radar(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles viewer
        WHERE viewer.id = p_user_id
          AND viewer.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(REGEXP_REPLACE(BTRIM(COALESCE(viewer.role, '')), '[_-]+', ' ', 'g')) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'MANAGER', 'SUPERVISOR', 'GENERAL MANAGER', 'GM', 'CEO'
              )
              OR UPPER(REGEXP_REPLACE(BTRIM(COALESCE(viewer.job_title, '')), '[_-]+', ' ', 'g')) IN (
                  'IT MANAGER', 'GENERAL MANAGER', 'GM', 'CEO', 'CHIEF EXECUTIVE OFFICER'
              )
          )
    );
$$;


--
-- Name: can_view_request_workflow(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_request_workflow(p_workflow_id uuid, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS(
        SELECT 1 FROM public.request_approval_workflows w
        WHERE w.id=p_workflow_id AND (
            w.employee_id=p_user_id OR
            EXISTS(SELECT 1 FROM public.request_approval_steps s WHERE s.workflow_id=w.id AND s.approver_id=p_user_id) OR
            EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=p_user_id AND upper(COALESCE(p.role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN'))
        )
    );
$$;


--
-- Name: can_view_task(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_task(p_task_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tasks t
        LEFT JOIN public.projects project ON project.id = t.project_id
        WHERE t.id = p_task_id
          AND p_user_id IS NOT NULL
          AND (
              public.is_task_admin(p_user_id)
              OR p_user_id IN (t.created_by, t.assignee_id, t.supervisor_id)
              OR EXISTS (
                  SELECT 1 FROM public.departments task_department
                  WHERE task_department.name = t.department
                    AND task_department.head_id = p_user_id
              )
              OR p_user_id = ANY(COALESCE(t.watchers, '{}'))
              OR p_user_id = ANY(COALESCE(t.visible_to, '{}'))
              OR p_user_id = ANY(COALESCE(project.assigned_people, '{}'))
              OR t.visibility = 'public'
              OR (
                  t.visibility = 'team'
                  AND EXISTS (
                      SELECT 1
                      FROM public.profiles viewer
                      JOIN public.profiles owner
                        ON owner.id IN (t.created_by, t.assignee_id)
                      WHERE viewer.id = p_user_id
                        AND (
                            viewer.department_id = owner.department_id
                            OR owner.manager_id = p_user_id
                            OR viewer.manager_id = owner.manager_id
                        )
                  )
              )
          )
    );
$$;


--
-- Name: can_view_task_list(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_task_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: can_view_task_list_via_employee_grant(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_task_list_via_employee_grant(p_list_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: can_view_task_via_employee_grant(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_view_task_via_employee_grant(p_task_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: change_crm_deal_stage(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.change_crm_deal_stage(p_deal_id uuid, p_new_stage text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_new_stage text := UPPER(BTRIM(COALESCE(p_new_stage, '')));
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to change CRM deals' USING ERRCODE = '42501';
    END IF;

    IF v_new_stage NOT IN ('LEAD', 'QUALIFICATION', 'PITCH', 'PROPOSAL', 'NEGOTIATION', 'WON', 'LOST') THEN
        RAISE EXCEPTION 'Invalid CRM deal stage' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_deal
      FROM public.crm_deals
     WHERE id = p_deal_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002';
    END IF;

    IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' AND v_new_stage = 'LOST' THEN
        RAISE EXCEPTION 'Lost deals must be deliberately reopened before editing' USING ERRCODE = '42501';
    END IF;

    -- Presentation, Discussion and Won are workflow-controlled stages.  The
    -- dedicated approval/project RPCs are the only paths that may establish
    -- those states; a mobile client cannot bypass them with a PATCH request.
    IF v_new_stage = 'PITCH'
       AND COALESCE(v_deal.workflow_status, '') NOT IN (
           'PENDING_APPROVAL', 'APPROVED', 'DESIGN_IN_PROGRESS',
           'DESIGN_PENDING_APPROVAL', 'DESIGN_REJECTED'
       ) THEN
        RAISE EXCEPTION 'Start the Presentation approval workflow before entering this stage' USING ERRCODE = '42501';
    END IF;

    IF v_new_stage IN ('NEGOTIATION', 'WON')
       AND COALESCE(v_deal.workflow_status, '') <> 'APPROVED' THEN
        RAISE EXCEPTION 'Complete all required approvals before advancing this deal' USING ERRCODE = '42501';
    END IF;

    UPDATE public.crm_deals
       SET stage = v_new_stage,
           proposal_sent_at = CASE
               WHEN v_new_stage = 'PROPOSAL' AND proposal_sent_at IS NULL THEN now()
               ELSE proposal_sent_at
           END
     WHERE id = v_deal.id;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, actor_id)
    VALUES (v_deal.id, 'STAGE_CHANGED', v_deal.stage, v_new_stage, auth.uid());

    RETURN jsonb_build_object(
        'deal_id', v_deal.id,
        'from_stage', v_deal.stage,
        'to_stage', v_new_stage,
        'actor_id', auth.uid()
    );
END;
$$;


--
-- Name: change_project_status(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.change_project_status(p_project_id uuid, p_status text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_project public.projects%ROWTYPE;
    v_status text := UPPER(BTRIM(COALESCE(p_status, '')));
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    IF NOT public.is_project_portfolio_admin(auth.uid()) THEN
        SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
        IF NOT FOUND OR (v_project.created_by <> auth.uid() AND v_project.project_manager_id <> auth.uid()) THEN
            RAISE EXCEPTION 'Only the project owner or manager can change project status' USING ERRCODE = '42501';
        END IF;
    ELSE
        SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
    END IF;
    IF v_status NOT IN ('PLANNING','ACTIVE','ON_HOLD','COMPLETED','CANCELLED') THEN
        RAISE EXCEPTION 'Invalid project status' USING ERRCODE = '22023';
    END IF;

    UPDATE public.projects
       SET lifecycle_status = v_status,
           project_status = CASE v_status
               WHEN 'PLANNING' THEN 'Planning'
               WHEN 'ACTIVE' THEN 'In Progress'
               WHEN 'ON_HOLD' THEN 'On Hold'
               WHEN 'COMPLETED' THEN 'Completed'
               WHEN 'CANCELLED' THEN 'Cancelled'
           END,
           updated_at = NOW()
     WHERE id = p_project_id;

    IF to_regclass('public.project_updates') IS NOT NULL THEN
        INSERT INTO public.project_updates(project_id, author_id, update_type, summary)
        VALUES (p_project_id, auth.uid(), 'UPDATE', format('Project status changed to %s', v_status));
    END IF;
    RETURN jsonb_build_object('project_id', p_project_id, 'status', v_status, 'actor_id', auth.uid());
END;
$$;


--
-- Name: change_task_status(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.change_task_status(p_task_id uuid, p_status text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_status text := NULLIF(BTRIM(COALESCE(p_status, '')), '');
    v_can_manage boolean := false;
BEGIN
    IF auth.uid() IS NULL OR v_status IS NULL THEN
        RAISE EXCEPTION 'A task and status are required' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT EXISTS (
        SELECT 1
          FROM public.profiles profile
         WHERE profile.id = auth.uid()
           AND profile.is_active IS DISTINCT FROM false
           AND (
               profile.id IN (v_task.created_by, v_task.assignee_id, v_task.supervisor_id)
               OR auth.uid() = ANY(COALESCE(v_task.assignee_ids, '{}'::uuid[]))
               OR UPPER(COALESCE(profile.role, '')) IN ('ADMIN', 'MANAGER', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN', 'CEO', 'GM', 'GENERAL MANAGER')
               OR UPPER(COALESCE(profile.job_title, '')) IN ('CEO', 'GM', 'GENERAL MANAGER')
           )
    ) INTO v_can_manage;

    IF NOT v_can_manage THEN
        RAISE EXCEPTION 'You are not authorized to change this task' USING ERRCODE = '42501';
    END IF;

    UPDATE public.tasks SET status = v_status WHERE id = v_task.id;

    RETURN jsonb_build_object(
        'task_id', v_task.id,
        'from_status', v_task.status,
        'to_status', v_status,
        'actor_id', auth.uid()
    );
END;
$$;


--
-- Name: clean_task_history_on_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clean_task_history_on_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    -- 1. Remove related task attachments from task_attachments table
    IF to_regclass('public.task_attachments') IS NOT NULL THEN
        DELETE FROM public.task_attachments WHERE task_id = OLD.id;
    END IF;

    -- 2. Remove related task comments from task_comments table
    IF to_regclass('public.task_comments') IS NOT NULL THEN
        DELETE FROM public.task_comments WHERE task_id = OLD.id;
    END IF;

    -- 3. Remove queued or sent emails for this task from task_email_outbox
    IF to_regclass('public.task_email_outbox') IS NOT NULL THEN
        DELETE FROM public.task_email_outbox WHERE task_id = OLD.id;
    END IF;

    -- 4. Remove notifications linked to this task id or mentioning this task title
    IF to_regclass('public.notifications') IS NOT NULL THEN
        DELETE FROM public.notifications
        WHERE task_id = OLD.id
           OR (metadata->>'task_title' IS NOT NULL AND metadata->>'task_title' = OLD.title)
           OR action_url LIKE '%task=' || OLD.id::text || '%';
    END IF;

    -- 5. Clean up CRM design task approval steps if table exists
    IF to_regclass('public.crm_design_task_approval_steps') IS NOT NULL THEN
        DELETE FROM public.crm_design_task_approval_steps WHERE task_id = OLD.id;
    END IF;

    -- 6. Unlink from CRM deals if referenced
    IF to_regclass('public.crm_deals') IS NOT NULL THEN
        UPDATE public.crm_deals
        SET design_task_id = NULL
        WHERE design_task_id = OLD.id;
    END IF;

    RETURN OLD;
END;
$$;


--
-- Name: create_crm_design_task_for_deal(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_crm_design_task_for_deal(p_deal_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_designer uuid;
    v_list_id uuid;
    v_department text;
    v_task_id uuid;
    v_watchers uuid[];
    v_notification_id uuid;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND OR v_deal.approval_type <> 'QUOTE_PROPOSAL' OR v_deal.workflow_status <> 'APPROVED' THEN
        RAISE EXCEPTION 'The quote and proposal approval must be completed first';
    END IF;
    SELECT id INTO v_designer FROM public.profiles WHERE emp_index = 8 AND is_active IS DISTINCT FROM false LIMIT 1;
    IF v_designer IS NULL THEN RAISE EXCEPTION 'Employee MQ-08 must be configured'; END IF;

    SELECT list.id, COALESCE(department.name, 'Design') INTO v_list_id, v_department
    FROM public.task_lists list LEFT JOIN public.departments department ON department.id = list.department_id
    WHERE COALESCE(list.name, '') ~* '(design|تصميم)'
    ORDER BY CASE WHEN COALESCE(list.name, '') ~* '^design$' THEN 0 ELSE 1 END, list.created_at LIMIT 1;
    IF v_list_id IS NULL THEN RAISE EXCEPTION 'The Design task list must be configured'; END IF;

    SELECT array_agg(DISTINCT approver_id) INTO v_watchers
    FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;
    PERFORM set_config('app.crm_design_task_creation', 'on', true);
    INSERT INTO public.tasks(
        title, title_i18n, description, description_i18n, assignee_id, created_by, status, priority, category,
        visibility, task_list_id, department, sub_type, content_type, watchers,
        visible_to, notify_via_email, crm_deal_id, crm_workflow_kind
    ) VALUES (
        'Design approved proposal: ' || v_deal.title,
        jsonb_build_object('en', 'Design approved proposal: ' || v_deal.title, 'ar', 'تصميم العرض المعتمد: ' || v_deal.title),
        COALESCE(v_deal.technical_description, 'Prepare the approved CRM proposal design.'),
        jsonb_build_object(
            'en', COALESCE(v_deal.technical_description, 'Prepare the approved CRM proposal design.'),
            'ar', COALESCE(v_deal.technical_description, 'إعداد تصميم عرض إدارة علاقات العملاء المعتمد.')
        ),
        v_designer, COALESCE(v_deal.created_by, v_deal.assigned_to, auth.uid()), 'todo', 'high', 'CRM',
        'private', v_list_id, v_department, 'Designing Task', 'Proposal', COALESCE(v_watchers, '{}'),
        COALESCE(v_watchers, '{}'), false, p_deal_id, 'QUOTE_PROPOSAL_DESIGN'
    ) RETURNING id INTO v_task_id;

    UPDATE public.crm_deals SET design_task_id = v_task_id, workflow_status = 'DESIGN_IN_PROGRESS' WHERE id = p_deal_id;

    SELECT id INTO v_notification_id FROM public.notifications
    WHERE task_id = v_task_id AND user_id = v_designer ORDER BY created_at DESC LIMIT 1;
    IF v_notification_id IS NULL THEN
        INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
        VALUES (v_designer, 'New CRM proposal Design task: ' || v_deal.title, 'crm_design_task_assigned', v_task_id, auth.uid(), '/?view=tasks', jsonb_build_object('deal_id', p_deal_id))
        RETURNING id INTO v_notification_id;
    ELSE
        UPDATE public.notifications
           SET message = 'New CRM proposal Design task: ' || v_deal.title,
               event_type = 'crm_design_task_assigned',
               metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('deal_id', p_deal_id)
         WHERE id = v_notification_id;
    END IF;
    INSERT INTO public.task_email_outbox(notification_id, task_id, recipient_id, recipient_email, subject, message, action_url, always_send)
    SELECT v_notification_id, v_task_id, profile.id, auth_user.email,
           'New CRM proposal Design task: ' || v_deal.title,
           'A new CRM proposal Design task has been assigned to you.', '/?view=tasks', true
    FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
    WHERE profile.id = v_designer AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.task_email_outbox outbox WHERE outbox.task_id = v_task_id AND outbox.recipient_id = v_designer);
    RETURN v_task_id;
END;
$_$;


--
-- Name: create_project_from_won_deal(uuid, date, date, date, date, text, numeric, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_project_from_won_deal(p_deal_id uuid, p_event_date date, p_start_date date, p_end_date date, p_uninstallation_date date, p_event_location text, p_project_amount numeric, p_paid_amount numeric, p_project_status text, p_notes text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_project_id UUID;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deal not found'; END IF;
    IF COALESCE(v_deal.workflow_status, 'NOT_STARTED') <> 'APPROVED' THEN
        RAISE EXCEPTION 'All internal approvals must be completed first';
    END IF;
    IF auth.uid() <> v_deal.assigned_to AND NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('ADMIN', 'MANAGER')
    ) THEN RAISE EXCEPTION 'Only the deal owner or a manager can create its project'; END IF;

    INSERT INTO public.projects (
        project_name, project_type, description, assigned_people, project_tags,
        deal_id, client_id, event_date, start_date, end_date, uninstallation_date,
        event_location, project_amount, paid_amount, project_status, source
    ) VALUES (
        v_deal.title, 'Client', p_notes,
        CASE WHEN v_deal.assigned_to IS NULL THEN ARRAY[]::UUID[] ELSE ARRAY[v_deal.assigned_to] END,
        ARRAY['Won Deal']::TEXT[], p_deal_id, v_deal.client_id, p_event_date,
        p_start_date, p_end_date, p_uninstallation_date, p_event_location,
        COALESCE(p_project_amount, v_deal.amount, 0), COALESCE(p_paid_amount, 0),
        COALESCE(NULLIF(p_project_status, ''), 'Not Confirmed'), 'WON_DEAL'
    )
    ON CONFLICT (deal_id) WHERE deal_id IS NOT NULL DO UPDATE SET
        event_date = EXCLUDED.event_date,
        start_date = EXCLUDED.start_date,
        end_date = EXCLUDED.end_date,
        uninstallation_date = EXCLUDED.uninstallation_date,
        event_location = EXCLUDED.event_location,
        project_amount = EXCLUDED.project_amount,
        paid_amount = EXCLUDED.paid_amount,
        project_status = EXCLUDED.project_status,
        description = EXCLUDED.description
    RETURNING id INTO v_project_id;

    UPDATE public.crm_deals SET stage = 'WON' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity (deal_id, action, from_status, to_status, note, actor_id)
    VALUES (p_deal_id, 'PROJECT_CREATED', v_deal.stage, 'WON', p_notes, auth.uid());
    RETURN v_project_id;
END;
$$;


--
-- Name: create_project_from_won_deal_v2(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_project_from_won_deal_v2(p_deal_id uuid, p_order jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_project_id uuid;
    v_assigned uuid[];
    v_event_date date;
    v_event_end_date date;
    v_event_start_time time;
    v_installation_time timestamp without time zone;
    v_uninstallation_time timestamp without time zone;
    v_equipment jsonb;
BEGIN
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deal not found'; END IF;
    IF v_deal.workflow_status <> 'APPROVED' THEN RAISE EXCEPTION 'Complete the deal workflow before opening the project'; END IF;
    IF auth.uid() NOT IN (COALESCE(v_deal.created_by, auth.uid()), COALESCE(v_deal.assigned_to, auth.uid()))
       AND NOT public.is_crm_approval_admin(auth.uid())
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND UPPER(COALESCE(p.role, '')) = 'MANAGER') THEN
        RAISE EXCEPTION 'Only the deal team or management can open this project';
    END IF;

    SELECT COALESCE(array_agg(value::uuid), '{}') INTO v_assigned
    FROM jsonb_array_elements_text(COALESCE(p_order->'assigned_people', '[]'::jsonb)) value;

    IF NULLIF(BTRIM(COALESCE(p_order->>'event_date', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->>'event_start_time', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->'client'->>'name', '')), '') IS NULL
       OR NULLIF(BTRIM(COALESCE(p_order->>'installation_type', '')), '') IS NULL THEN
        RAISE EXCEPTION 'Event date, starting time, client name, and installation type are required';
    END IF;

    v_event_date := (p_order->>'event_date')::date;
    v_event_end_date := COALESCE(NULLIF(p_order->>'event_end_date', '')::date, v_event_date);
    v_event_start_time := (p_order->>'event_start_time')::time;
    IF v_event_end_date < v_event_date THEN
        RAISE EXCEPTION 'Event End Date cannot be before the Event Date';
    END IF;
    v_installation_time := COALESCE(
        NULLIF(p_order->>'installation_time', '')::timestamp,
        (v_event_date + v_event_start_time) - INTERVAL '2 days'
    );
    v_uninstallation_time := COALESCE(
        NULLIF(p_order->>'uninstallation_time', '')::timestamp,
        (v_event_end_date + v_event_start_time) + INTERVAL '2 days'
    );

    IF COALESCE(array_length(v_assigned, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one employee';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM unnest(v_assigned) assignee_id
        LEFT JOIN public.profiles profile ON profile.id = assignee_id
        WHERE profile.id IS NULL OR profile.is_active IS FALSE
    ) THEN
        RAISE EXCEPTION 'Projects can only be assigned to active employees';
    END IF;

    IF p_order ? 'equipment' AND jsonb_typeof(p_order->'equipment') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Equipment must be an array';
    END IF;
    v_equipment := CASE
        WHEN jsonb_typeof(p_order->'equipment') = 'array' THEN p_order->'equipment'
        ELSE '[]'::jsonb
    END;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_equipment) equipment_item
        WHERE NULLIF(BTRIM(COALESCE(equipment_item->>'item', '')), '') IS NULL
           OR NULLIF(BTRIM(COALESCE(equipment_item->>'quantity', '')), '') IS NULL
    ) THEN
        RAISE EXCEPTION 'Every added equipment item needs an item name and quantity';
    END IF;

    SELECT id INTO v_project_id FROM public.projects WHERE deal_id = p_deal_id ORDER BY created_at LIMIT 1 FOR UPDATE;
    IF v_project_id IS NULL THEN
        INSERT INTO public.projects(
            project_name, project_type, description, assigned_people, project_tags,
            deal_id, client_id, event_date, start_date, end_date, event_location, project_amount,
            paid_amount, project_status, source, order_employee_id, event_start_time,
            installation_time, uninstallation_time, client_snapshot, event_location_text,
            installation_type, equipment
        ) VALUES (
            v_deal.title, 'Client', NULLIF(p_order->>'notes', ''), v_assigned, ARRAY['Won Deal']::text[],
            v_deal.id, v_deal.client_id, v_event_date, v_event_date, v_event_end_date,
            NULLIF(p_order->>'location_url', ''), COALESCE(NULLIF(p_order->>'project_amount', '')::numeric, v_deal.amount, 0),
            COALESCE(NULLIF(p_order->>'paid_amount', '')::numeric, 0), 'Not Confirmed', 'WON_DEAL',
            auth.uid(), v_event_start_time, v_installation_time, v_uninstallation_time,
            p_order->'client', NULLIF(p_order->>'location_text', ''),
            p_order->>'installation_type', v_equipment
        ) RETURNING id INTO v_project_id;
    ELSE
        UPDATE public.projects SET
            description = NULLIF(p_order->>'notes', ''), assigned_people = v_assigned,
            event_date = v_event_date, start_date = v_event_date, end_date = v_event_end_date,
            event_location = NULLIF(p_order->>'location_url', ''),
            project_amount = COALESCE(NULLIF(p_order->>'project_amount', '')::numeric, v_deal.amount, 0),
            paid_amount = COALESCE(NULLIF(p_order->>'paid_amount', '')::numeric, 0),
            order_employee_id = auth.uid(), event_start_time = v_event_start_time,
            installation_time = v_installation_time, uninstallation_time = v_uninstallation_time,
            client_snapshot = p_order->'client', event_location_text = NULLIF(p_order->>'location_text', ''),
            installation_type = p_order->>'installation_type', equipment = v_equipment
        WHERE id = v_project_id;
    END IF;

    UPDATE public.crm_deals SET stage = 'WON' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (p_deal_id, 'PROJECT_CREATED', v_deal.stage, 'WON', NULLIF(p_order->>'notes', ''), auth.uid());
    RETURN v_project_id;
END;
$$;


--
-- Name: create_project_secure(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_project_secure(p_project jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_user UUID := auth.uid();
    v_project public.projects%ROWTYPE;
    v_project_manager UUID := NULLIF(p_project->>'project_manager_id', '')::UUID;
    v_assignees UUID[] := COALESCE(
        ARRAY(SELECT value::UUID FROM jsonb_array_elements_text(COALESCE(p_project->'assigned_people', '[]'::JSONB)) value),
        ARRAY[]::UUID[]
    );
    v_invalid UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    IF NULLIF(BTRIM(p_project->>'project_name'), '') IS NULL
       OR NULLIF(BTRIM(p_project->>'project_type'), '') IS NULL THEN
        RAISE EXCEPTION 'Project name and type are required' USING ERRCODE = '22023';
    END IF;
    IF v_project_manager IS NULL THEN v_project_manager := v_user; END IF;
    IF v_project_manager <> v_user AND NOT public.is_project_portfolio_admin(v_user) THEN
        RAISE EXCEPTION 'Only a portfolio administrator can create a project owned by another employee' USING ERRCODE = '42501';
    END IF;
    SELECT value INTO v_invalid
    FROM UNNEST(v_assignees) value
    WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = value AND p.is_active IS DISTINCT FROM FALSE)
    LIMIT 1;
    IF v_invalid IS NOT NULL THEN RAISE EXCEPTION 'Every project assignee must be active' USING ERRCODE = '22023'; END IF;

    INSERT INTO public.projects(
        project_name, project_type, description, assigned_people, project_category, project_tags,
        project_manager_id, created_by, lifecycle_status, health_status, priority, progress_percent,
        start_date, end_date, client_name, budget_amount, actual_cost
    ) VALUES (
        BTRIM(p_project->>'project_name'), BTRIM(p_project->>'project_type'), NULLIF(BTRIM(p_project->>'description'), ''),
        v_assignees, NULLIF(BTRIM(p_project->>'project_category'), ''),
        ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(p_project->'project_tags', '[]'::JSONB)) value),
        v_project_manager, v_user,
        COALESCE(NULLIF(UPPER(BTRIM(p_project->>'lifecycle_status')), ''), 'PLANNING'),
        COALESCE(NULLIF(UPPER(BTRIM(p_project->>'health_status')), ''), 'ON_TRACK'),
        COALESCE(NULLIF(UPPER(BTRIM(p_project->>'priority')), ''), 'MEDIUM'),
        COALESCE(NULLIF(p_project->>'progress_percent', '')::INTEGER, 0),
        NULLIF(p_project->>'start_date', '')::DATE, NULLIF(p_project->>'end_date', '')::DATE,
        NULLIF(BTRIM(p_project->>'client_name'), ''),
        CASE WHEN public.can_view_business_financials(v_user) THEN COALESCE(NULLIF(p_project->>'budget_amount', '')::NUMERIC, 0) ELSE 0 END,
        CASE WHEN public.can_view_business_financials(v_user) THEN COALESCE(NULLIF(p_project->>'actual_cost', '')::NUMERIC, 0) ELSE 0 END
    ) RETURNING * INTO v_project;
    RETURN to_jsonb(v_project) || jsonb_build_object(
        'project_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.project_amount) ELSE 'null'::JSONB END,
        'paid_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.paid_amount) ELSE 'null'::JSONB END,
        'budget_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.budget_amount) ELSE 'null'::JSONB END,
        'actual_cost', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_project.actual_cost) ELSE 'null'::JSONB END
    );
END;
$$;


--
-- Name: project_updates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_updates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    author_id uuid NOT NULL,
    update_type text DEFAULT 'UPDATE'::text NOT NULL,
    summary text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT project_updates_summary_check CHECK (((char_length(btrim(summary)) >= 1) AND (char_length(btrim(summary)) <= 4000))),
    CONSTRAINT project_updates_update_type_check CHECK ((update_type = ANY (ARRAY['UPDATE'::text, 'DECISION'::text, 'MILESTONE'::text, 'RISK'::text])))
);


--
-- Name: create_project_update_secure(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_project_update_secure(p_project_id uuid, p_summary text, p_update_type text DEFAULT 'UPDATE'::text) RETURNS public.project_updates
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_update public.project_updates%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_project(p_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    IF NULLIF(BTRIM(p_summary), '') IS NULL THEN RAISE EXCEPTION 'Project update is required' USING ERRCODE = '22023'; END IF;
    INSERT INTO public.project_updates(project_id, author_id, update_type, summary)
    VALUES (p_project_id, auth.uid(), UPPER(COALESCE(p_update_type, 'UPDATE')), BTRIM(p_summary))
    RETURNING * INTO v_update;
    RETURN v_update;
END;
$$;


--
-- Name: task_lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_lists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid NOT NULL,
    name text NOT NULL,
    shared_with uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    department_id uuid,
    visible_to_all boolean DEFAULT false NOT NULL,
    can_add_users uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    can_delete_users uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    description text,
    template text DEFAULT 'none'::text NOT NULL,
    notify_assignee boolean DEFAULT false NOT NULL,
    notify_complete boolean DEFAULT false NOT NULL,
    CONSTRAINT task_lists_name_check CHECK (((char_length(btrim(name)) >= 1) AND (char_length(btrim(name)) <= 80)))
);


--
-- Name: create_task_list_for_user(text, uuid[], uuid, boolean, uuid[], uuid[], text, text, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_task_list_for_user(p_name text, p_shared_with uuid[] DEFAULT '{}'::uuid[], p_department_id uuid DEFAULT NULL::uuid, p_visible_to_all boolean DEFAULT false, p_can_add_users uuid[] DEFAULT '{}'::uuid[], p_can_delete_users uuid[] DEFAULT '{}'::uuid[], p_description text DEFAULT NULL::text, p_template text DEFAULT 'none'::text, p_notify_assignee boolean DEFAULT false, p_notify_complete boolean DEFAULT false) RETURNS public.task_lists
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: create_task_secure(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_task_secure(p_payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_assignees uuid[];
    v_assignee_id uuid;
    v_project_id uuid;
    v_task_list_id uuid;
    v_payload jsonb := COALESCE(p_payload, '{}'::jsonb);
    v_result jsonb;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    IF NULLIF(BTRIM(v_payload->>'title'), '') IS NULL THEN
        RAISE EXCEPTION 'Task title is required' USING ERRCODE = '22023';
    END IF;
    v_assignee_id := NULLIF(v_payload->>'assignee_id', '')::uuid;
    v_assignees := ARRAY(
        SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(v_payload->'assignee_ids', '[]'::jsonb)) value
    );
    IF v_assignee_id IS NOT NULL AND NOT (v_assignee_id = ANY(COALESCE(v_assignees, '{}'::uuid[]))) THEN
        v_assignees := array_prepend(v_assignee_id, COALESCE(v_assignees, '{}'::uuid[]));
    END IF;
    IF EXISTS (
        SELECT 1 FROM UNNEST(COALESCE(v_assignees, '{}'::uuid[])) assignee_id
        WHERE NOT EXISTS (SELECT 1 FROM public.profiles profile WHERE profile.id = assignee_id AND profile.is_active IS DISTINCT FROM false)
    ) THEN RAISE EXCEPTION 'Every assignee must be an active employee' USING ERRCODE = '22023'; END IF;
    v_project_id := NULLIF(v_payload->>'project_id', '')::uuid;
    v_task_list_id := NULLIF(v_payload->>'task_list_id', '')::uuid;
    IF v_project_id IS NOT NULL AND NOT public.can_access_project(v_project_id, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    IF v_task_list_id IS NOT NULL AND NOT public.can_add_task_to_list(v_task_list_id, auth.uid()) THEN
        RAISE EXCEPTION 'Task-list access denied' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.tasks (
        title, description, assignee_id, assignee_ids, supervisor_id, created_by,
        due_date, status, priority, category, title_i18n, description_i18n,
        start_date, end_date, estimated_time, visibility, project_id, tags,
        visible_to, content_type, source_link, upload_link, department, sub_type,
        watchers, parent_task_id, marketing_department, content_links,
        submission_links, delivery_status, task_list_id, repeat_type,
        repeat_interval, notify_via_email, crm_deal_id, crm_workflow_kind
    )
    VALUES (
        BTRIM(v_payload->>'title'), NULLIF(v_payload->>'description', ''),
        v_assignee_id, COALESCE(v_assignees, '{}'::uuid[]),
        NULLIF(v_payload->>'supervisor_id', '')::uuid, auth.uid(),
        NULLIF(v_payload->>'due_date', '')::date,
        COALESCE(NULLIF(v_payload->>'status', ''), 'todo'),
        COALESCE(NULLIF(v_payload->>'priority', ''), 'medium'),
        COALESCE(NULLIF(v_payload->>'category', ''), 'General'),
        COALESCE(v_payload->'title_i18n', '{}'::jsonb),
        COALESCE(v_payload->'description_i18n', '{}'::jsonb),
        NULLIF(v_payload->>'start_date', '')::date,
        NULLIF(v_payload->>'end_date', '')::date,
        NULLIF(v_payload->>'estimated_time', '')::integer,
        COALESCE(NULLIF(v_payload->>'visibility', ''), 'public'),
        v_project_id,
        ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(v_payload->'tags', '[]'::jsonb)) value),
        ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(v_payload->'visible_to', '[]'::jsonb)) value),
        NULLIF(v_payload->>'content_type', ''), NULLIF(v_payload->>'source_link', ''),
        NULLIF(v_payload->>'upload_link', ''), NULLIF(v_payload->>'department', ''),
        NULLIF(v_payload->>'sub_type', ''),
        ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(COALESCE(v_payload->'watchers', '[]'::jsonb)) value),
        NULLIF(v_payload->>'parent_task_id', '')::uuid,
        NULLIF(v_payload->>'marketing_department', ''),
        ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(v_payload->'content_links', '[]'::jsonb)) value),
        ARRAY(SELECT value FROM jsonb_array_elements_text(COALESCE(v_payload->'submission_links', '[]'::jsonb)) value),
        NULLIF(v_payload->>'delivery_status', ''), v_task_list_id,
        COALESCE(NULLIF(v_payload->>'repeat_type', ''), 'NONE'),
        COALESCE(NULLIF(v_payload->>'repeat_interval', '')::integer, 1),
        COALESCE((v_payload->>'notify_via_email')::boolean, false),
        NULLIF(v_payload->>'crm_deal_id', '')::uuid,
        NULLIF(v_payload->>'crm_workflow_kind', '')
    )
    RETURNING to_jsonb(tasks) INTO v_result;
    RETURN v_result;
END;
$$;


--
-- Name: create_user_by_admin(text, text, character varying, character varying, character varying, character varying, character varying, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_user_by_admin(new_email text, new_password text, new_role character varying DEFAULT 'EMPLOYEE'::character varying, new_job_title character varying DEFAULT NULL::character varying, new_full_name character varying DEFAULT NULL::character varying, new_iqama character varying DEFAULT NULL::character varying, new_phone character varying DEFAULT NULL::character varying, new_employee_id text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
    new_user_id UUID := gen_random_uuid();
    authorized BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(COALESCE(p.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
              OR UPPER(COALESCE(p.job_title, '')) = 'HR MANAGER'
          )
    ) INTO authorized;

    IF NOT authorized THEN
        RAISE EXCEPTION 'Unauthorized: only Admin or HR Manager accounts can create users'
            USING ERRCODE = '42501';
    END IF;

    IF NULLIF(BTRIM(new_email), '') IS NULL OR NULLIF(new_password, '') IS NULL THEN
        RAISE EXCEPTION 'Email and password are required' USING ERRCODE = '22023';
    END IF;

    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at, confirmation_token, email_change,
        email_change_token_new, recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated',
        LOWER(BTRIM(new_email)), extensions.crypt(new_password, extensions.gen_salt('bf')),
        now(), '{"provider":"email","providers":["email"]}', '{}',
        now(), now(), '', '', '', ''
    );

    INSERT INTO auth.identities (
        provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id
    ) VALUES (
        new_user_id::text, new_user_id,
        jsonb_build_object('sub', new_user_id::text, 'email', LOWER(BTRIM(new_email))),
        'email', now(), now(), now(), gen_random_uuid()
    );

    INSERT INTO public.profiles (id, role, job_title, full_name, iqama_number, phone_number, emp_index)
    VALUES (
        new_user_id, UPPER(COALESCE(NULLIF(BTRIM(new_role), ''), 'EMPLOYEE')),
        NULLIF(BTRIM(new_job_title), ''), NULLIF(BTRIM(new_full_name), ''),
        NULLIF(BTRIM(new_iqama), ''), NULLIF(BTRIM(new_phone), ''),
        NULLIF(BTRIM(new_employee_id), '')::integer
    );

    RETURN new_user_id;
END;
$$;


--
-- Name: decide_crm_design_task_approval(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decide_crm_design_task_approval(p_step_id uuid, p_decision text, p_note text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_step public.crm_design_task_approval_steps%ROWTYPE;
    v_task public.tasks%ROWTYPE;
    v_deal public.crm_deals%ROWTYPE;
    v_remaining integer;
    v_notification_id uuid;
BEGIN
    p_decision := UPPER(BTRIM(COALESCE(p_decision, '')));
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'Invalid approval decision'; END IF;
    IF p_decision = 'REJECTED' AND NULLIF(BTRIM(COALESCE(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'A rejection reason is required'; END IF;
    SELECT * INTO v_step FROM public.crm_design_task_approval_steps WHERE id = p_step_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Design approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;
    UPDATE public.crm_design_task_approval_steps SET status = p_decision, decision_note = NULLIF(BTRIM(p_note), ''), decided_at = now()
    WHERE id = p_step_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval has already been decided'; END IF;
    SELECT * INTO v_task FROM public.tasks WHERE id = v_step.task_id;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_step.deal_id;
    IF p_decision = 'REJECTED' THEN
        UPDATE public.tasks SET status = 'in_progress', completion_requested_by = NULL, completion_requested_at = NULL WHERE id = v_task.id;
        UPDATE public.crm_deals SET workflow_status = 'DESIGN_REJECTED' WHERE id = v_deal.id;
        SELECT id INTO v_notification_id FROM public.notifications
        WHERE task_id = v_task.id AND user_id = v_task.assignee_id
        ORDER BY created_at DESC LIMIT 1;
        IF v_notification_id IS NULL THEN
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            VALUES (v_task.assignee_id, 'CRM Design task rejected: ' || v_task.title || '. Reason: ' || BTRIM(p_note), 'crm_design_task_rejected', v_task.id, auth.uid(), '/?view=tasks', jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note)))
            RETURNING id INTO v_notification_id;
        ELSE
            UPDATE public.notifications
               SET message = 'CRM Design task rejected: ' || v_task.title || '. Reason: ' || BTRIM(p_note),
                   event_type = 'crm_design_task_rejected',
                   metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note))
             WHERE id = v_notification_id;
        END IF;
        INSERT INTO public.task_email_outbox(notification_id, task_id, recipient_id, recipient_email, subject, message, action_url, always_send)
        SELECT v_notification_id, v_task.id, profile.id, auth_user.email, 'CRM Design task needs changes: ' || v_task.title,
               'Reason: ' || BTRIM(p_note), '/?view=tasks', true
        FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE profile.id = v_task.assignee_id AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
    ELSE
        SELECT count(*) INTO v_remaining FROM public.crm_design_task_approval_steps WHERE task_id = v_task.id AND status <> 'APPROVED';
        IF v_remaining = 0 THEN
            PERFORM set_config('app.crm_design_task_finalize', 'on', true);
            UPDATE public.tasks SET status = 'completed', completion_approved_by = auth.uid(), completion_approved_at = now() WHERE id = v_task.id;
            UPDATE public.crm_deals SET stage = 'NEGOTIATION', workflow_status = 'APPROVED' WHERE id = v_deal.id;
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            SELECT recipient, 'CRM Design approved and deal moved to Discussion: ' || v_deal.title,
                   'crm_design_task_approved', v_task.id, auth.uid(), '/?view=crm', jsonb_build_object('deal_id', v_deal.id)
            FROM unnest(array_remove(ARRAY[v_task.assignee_id, COALESCE(v_deal.created_by, v_deal.assigned_to)], NULL)) recipient;
        END IF;
    END IF;
END;
$$;


--
-- Name: decide_deal_approval(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decide_deal_approval(p_step_id uuid, p_decision text, p_note text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_step public.crm_deal_approval_steps%ROWTYPE;
    v_deal public.crm_deals%ROWTYPE;
    v_remaining integer;
    v_owner uuid;
BEGIN
    p_decision := UPPER(BTRIM(COALESCE(p_decision, '')));
    IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'Invalid approval decision'; END IF;
    IF p_decision = 'REJECTED' AND NULLIF(BTRIM(COALESCE(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A rejection reason is required';
    END IF;

    SELECT * INTO v_step
      FROM public.crm_deal_approval_steps
     WHERE id = p_step_id
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Approval step not found'; END IF;
    IF v_step.approver_id IS DISTINCT FROM auth.uid() AND NOT public.is_crm_approval_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Only the assigned approver or an administrator can decide this request';
    END IF;

    UPDATE public.crm_deal_approval_steps
       SET status = p_decision,
           decision_note = NULLIF(BTRIM(p_note), ''),
           decided_at = now()
     WHERE id = p_step_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'This approval has already been decided'; END IF;

    SELECT * INTO v_deal FROM public.crm_deals WHERE id = v_step.deal_id;
    v_owner := COALESCE(v_deal.created_by, v_deal.assigned_to);

    IF p_decision = 'REJECTED' THEN
        UPDATE public.crm_deals SET workflow_status = 'REJECTED' WHERE id = v_step.deal_id;
        IF v_owner IS NOT NULL THEN
            INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
            VALUES (
                v_owner,
                'CRM request rejected: ' || v_deal.title || '. Reason: ' || BTRIM(p_note),
                'crm_approval_rejected',
                auth.uid(),
                '/?view=crm',
                jsonb_build_object('deal_id', v_deal.id, 'reason', BTRIM(p_note), 'request_type', v_deal.approval_type)
            );
        END IF;
    ELSE
        SELECT count(*) INTO v_remaining
          FROM public.crm_deal_approval_steps
         WHERE deal_id = v_deal.id AND status <> 'APPROVED';

        IF v_remaining = 0 THEN
            IF v_deal.approval_type = 'QUOTE_PROPOSAL' THEN
                -- create_crm_design_task_for_deal requires APPROVED while it
                -- creates the task, then changes the status to DESIGN_IN_PROGRESS.
                UPDATE public.crm_deals
                   SET workflow_status = 'APPROVED',
                       stage = 'PITCH',
                       design_task_status = 'IN_PROGRESS'
                 WHERE id = v_deal.id;
                PERFORM public.create_crm_design_task_for_deal(v_deal.id);
            ELSE
                UPDATE public.crm_deals
                   SET workflow_status = 'APPROVED', stage = 'NEGOTIATION'
                 WHERE id = v_deal.id;
            END IF;

            IF v_owner IS NOT NULL THEN
                INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
                VALUES (
                    v_owner,
                    CASE WHEN v_deal.approval_type = 'QUOTE_PROPOSAL'
                         THEN 'CRM approval completed and Design task opened: '
                         ELSE 'CRM approval completed: ' END || v_deal.title,
                    'crm_approval_completed',
                    auth.uid(),
                    '/?view=crm',
                    jsonb_build_object('deal_id', v_deal.id, 'request_type', v_deal.approval_type)
                );
            END IF;
        END IF;
    END IF;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (v_deal.id, 'APPROVAL_DECISION', 'PENDING', p_decision, p_note, auth.uid());
END;
$$;


--
-- Name: decide_request_approval(text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decide_request_approval(p_source_table text, p_source_id uuid, p_decision text, p_note text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
    workflow public.request_approval_workflows%ROWTYPE;
    current_step public.request_approval_steps%ROWTYPE;
    next_step public.request_approval_steps%ROWTYPE;
    normalized TEXT;
    clean_note TEXT;
    display_stage TEXT;
    actor_is_admin BOOLEAN;
BEGIN
    normalized:=UPPER(BTRIM(COALESCE(p_decision,'')));
    clean_note:=NULLIF(BTRIM(COALESCE(p_note,'')),'');
    IF normalized NOT IN ('APPROVED','REJECTED') THEN
        RAISE EXCEPTION 'Decision must be APPROVED or REJECTED';
    END IF;
    IF normalized='REJECTED' AND clean_note IS NULL THEN
        RAISE EXCEPTION 'A rejection reason is required';
    END IF;

    SELECT EXISTS(
        SELECT 1
        FROM public.profiles
        WHERE id=auth.uid()
          AND (
              UPPER(COALESCE(role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN', 'OWNER')
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(job_title, ''), '[_-]+', ' ', 'g'))) IN ('GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER', 'MARKETING MANAGER')
              OR UPPER(COALESCE(employee_id,'')) IN ('MQ-04', 'MQ-05')
          )
    ) INTO actor_is_admin;

    SELECT * INTO workflow
    FROM public.request_approval_workflows
    WHERE source_table=p_source_table AND source_id=p_source_id
    FOR UPDATE;
    IF NOT FOUND OR workflow.status<>'PENDING' OR workflow.archived_at IS NOT NULL THEN
        RAISE EXCEPTION 'Request is not awaiting approval';
    END IF;

    SELECT * INTO current_step
    FROM public.request_approval_steps
    WHERE workflow_id=workflow.id AND step_order=workflow.current_step
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'The active approval stage is missing';
    END IF;
    IF current_step.approver_id<>auth.uid() AND NOT actor_is_admin THEN
        RAISE EXCEPTION 'This request is awaiting approval from another manager' USING ERRCODE='42501';
    END IF;
    IF current_step.status<>'PENDING' THEN
        RAISE EXCEPTION 'This approval stage has already been decided';
    END IF;
    IF EXISTS(
        SELECT 1
        FROM public.request_approval_steps
        WHERE workflow_id=workflow.id
          AND step_order<current_step.step_order
          AND status<>'APPROVED'
    ) THEN
        RAISE EXCEPTION 'A previous approval stage has not been approved';
    END IF;

    UPDATE public.request_approval_steps
    SET status=normalized,decision_note=clean_note,decided_at=NOW()
    WHERE id=current_step.id;
    display_stage:=INITCAP(REPLACE(current_step.stage_key,'_',' '));

    IF normalized='REJECTED' THEN
        UPDATE public.request_approval_workflows
        SET status='REJECTED',completed_at=NOW(),archived_at=NOW(),
            rejected_by=auth.uid(),rejection_reason=clean_note
        WHERE id=workflow.id;
        EXECUTE format(
            'UPDATE public.%I SET status=$1,is_archived=TRUE,archived_at=NOW(),rejection_reason=$2 WHERE id=$3',
            workflow.source_table
        ) USING 'REJECTED',clean_note,workflow.source_id;
        PERFORM public.queue_request_notification(
            workflow.employee_id,
            'Your '||workflow.request_type||' request was rejected by '||display_stage||'. Reason: '||clean_note||' The request has been archived.',
            'request_rejected',workflow.id
        );
        RETURN jsonb_build_object('status','REJECTED','archived',TRUE,'reason',clean_note);
    END IF;

    SELECT * INTO next_step
    FROM public.request_approval_steps
    WHERE workflow_id=workflow.id AND step_order=current_step.step_order+1;
    IF FOUND THEN
        UPDATE public.request_approval_workflows
        SET current_step=next_step.step_order
        WHERE id=workflow.id;
        PERFORM public.queue_request_notification(
            next_step.approver_id,
            'Approval required: '||workflow.request_type,
            'request_approval_required',workflow.id
        );
        PERFORM public.queue_request_notification(
            workflow.employee_id,
            'Your '||workflow.request_type||' request was approved by '||display_stage||' and moved to '||INITCAP(REPLACE(next_step.stage_key,'_',' '))||'.',
            'request_status_changed',workflow.id
        );
        RETURN jsonb_build_object('status','PENDING','current_step',next_step.step_order,'stage',next_step.stage_key);
    END IF;

    UPDATE public.request_approval_workflows
    SET status='APPROVED',completed_at=NOW()
    WHERE id=workflow.id;
    EXECUTE format('UPDATE public.%I SET status=$1 WHERE id=$2',workflow.source_table)
    USING 'APPROVED',workflow.source_id;
    PERFORM public.queue_request_notification(
        workflow.employee_id,
        'Your '||workflow.request_type||' request received final approval.',
        'request_approved',workflow.id
    );
    RETURN jsonb_build_object('status','APPROVED');
END;
$_$;


--
-- Name: delete_archived_contract(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_archived_contract(target_contract_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND UPPER(COALESCE(role, '')) = 'ADMIN') THEN
        RAISE EXCEPTION 'Only an administrator can permanently delete archived contracts';
    END IF;
    DELETE FROM public.contracts WHERE id = target_contract_id AND is_archived = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Archived contract not found'; END IF;
END; $$;


--
-- Name: delete_crm_deal(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_crm_deal(p_deal_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: delete_project_secure(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_project_secure(p_project_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_user UUID := auth.uid(); v_project public.projects%ROWTYPE;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id=p_project_id FOR UPDATE;
    IF NOT FOUND THEN RETURN FALSE; END IF;
    IF NOT (public.is_project_portfolio_admin(v_user) OR v_project.created_by=v_user OR v_project.project_manager_id=v_user) THEN
        RAISE EXCEPTION 'Only the project owner, manager, or administrator can delete this project' USING ERRCODE = '42501';
    END IF;
    DELETE FROM public.projects WHERE id=p_project_id;
    RETURN TRUE;
END;
$$;


--
-- Name: delete_project_todo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_project_todo(p_todo_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: delete_task_comment(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_task_comment(p_comment_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: delete_task_secure(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_task_secure(p_task_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_task public.tasks%ROWTYPE; v_can_delete boolean;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    SELECT task.* INTO v_task FROM public.tasks task WHERE task.id = p_task_id FOR UPDATE;
    IF NOT FOUND THEN RETURN false; END IF;
    SELECT (
        v_task.created_by = auth.uid()
        OR public.can_assign_tasks_company_wide(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.task_lists list
            WHERE list.id = v_task.task_list_id
              AND auth.uid() = ANY(COALESCE(list.can_delete_users, '{}'::uuid[]))
        )
    ) INTO v_can_delete;
    IF NOT v_can_delete THEN RAISE EXCEPTION 'You are not authorized to delete this task' USING ERRCODE = '42501'; END IF;
    DELETE FROM public.tasks WHERE id = p_task_id;
    RETURN true;
END;
$$;


--
-- Name: delete_user(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_user(target_user_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Only allow admins to execute
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Perform a soft delete by marking the user as inactive
    -- This prevents 409 Conflict errors from other tables that reference this user
    UPDATE public.profiles SET is_active = false WHERE id = target_user_id;
END;
$$;


--
-- Name: email_profile_name(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.email_profile_name(p_profile_id uuid) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT COALESCE(
        NULLIF(BTRIM(profile.full_name), ''),
        NULLIF(BTRIM(profile.display_name), ''),
        NULLIF(BTRIM(profile.display_name_ar), ''),
        'Unknown employee'
    )
    FROM public.profiles profile WHERE profile.id = p_profile_id;
$$;


--
-- Name: enforce_attendance_coordinates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_attendance_coordinates() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    manager_is_saving_map_link BOOLEAN := public.can_manage_attendance_records(auth.uid());
BEGIN
    IF (TG_OP = 'INSERT' OR NEW.clock_in_time IS DISTINCT FROM OLD.clock_in_time OR NEW.clock_in_location IS DISTINCT FROM OLD.clock_in_location)
       AND NEW.clock_in_time IS NOT NULL
       AND NOT public.is_valid_attendance_coordinates(NEW.clock_in_location)
       AND NOT (manager_is_saving_map_link AND public.is_valid_google_maps_location(NEW.clock_in_location)) THEN
        RAISE EXCEPTION 'Clock-in requires captured coordinates or an administrator Google Maps link' USING ERRCODE = '23514';
    END IF;
    IF (TG_OP = 'INSERT' OR NEW.clock_out_time IS DISTINCT FROM OLD.clock_out_time OR NEW.clock_out_location IS DISTINCT FROM OLD.clock_out_location)
       AND NEW.clock_out_time IS NOT NULL
       AND NOT public.is_valid_attendance_coordinates(NEW.clock_out_location)
       AND NOT (manager_is_saving_map_link AND public.is_valid_google_maps_location(NEW.clock_out_location)) THEN
        RAISE EXCEPTION 'Clock-out requires captured coordinates or an administrator Google Maps link' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: enforce_crm_deal_contact_requirements(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_crm_deal_contact_requirements() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    -- New deals must contain all required contact details. On legacy rows, run
    -- the same validation once any of these fields is intentionally changed;
    -- unrelated stage transitions remain possible until the deal is edited.
    IF TG_OP = 'INSERT'
       OR NEW.first_contact_date IS DISTINCT FROM OLD.first_contact_date
       OR NEW.contact_method IS DISTINCT FROM OLD.contact_method
       OR NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
        IF NEW.first_contact_date IS NULL THEN
            RAISE EXCEPTION 'First contact date is required' USING ERRCODE = '23514';
        END IF;
        IF NULLIF(BTRIM(NEW.contact_method), '') IS NULL THEN
            RAISE EXCEPTION 'Contact method is required' USING ERRCODE = '23514';
        END IF;
        IF NEW.assigned_to IS NULL THEN
            RAISE EXCEPTION 'Deal assignee is required' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: enforce_crm_design_task_completion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_crm_design_task_completion() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_approval record;
    v_notification_id uuid;
    v_submitter_name text;
    v_attachment_links jsonb;
BEGIN
    IF NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'
       AND LOWER(BTRIM(COALESCE(NEW.status, ''))) = 'completed'
       AND LOWER(BTRIM(COALESCE(OLD.status, ''))) IS DISTINCT FROM 'completed'
       AND current_setting('app.crm_design_task_finalize', true) IS DISTINCT FROM 'on' THEN

        IF COALESCE(cardinality(NEW.submission_links), 0) = 0 THEN
            RAISE EXCEPTION 'Upload at least one completed Design PDF or image before requesting approval'
                USING ERRCODE = '23514';
        END IF;

        SELECT * INTO v_deal
          FROM public.crm_deals
         WHERE id = NEW.crm_deal_id
         FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'The CRM deal linked to this Design task was not found'; END IF;

        -- Every resubmission starts a fresh unanimous approval round. The
        -- original Quote-and-Proposal group is CEO, GM, MQ-04, MQ-05 and the
        -- Marketing Manager, so copying it keeps both cycles aligned.
        DELETE FROM public.crm_design_task_approval_steps WHERE task_id = NEW.id;
        INSERT INTO public.crm_design_task_approval_steps(task_id, deal_id, step_order, stage_key, approver_id)
        SELECT NEW.id, NEW.crm_deal_id, step.step_order, step.stage_key, step.approver_id
          FROM public.crm_deal_approval_steps step
         WHERE step.deal_id = NEW.crm_deal_id
         ORDER BY step.step_order;

        IF NOT EXISTS (SELECT 1 FROM public.crm_design_task_approval_steps WHERE task_id = NEW.id) THEN
            RAISE EXCEPTION 'The Design approval team is not configured for this deal';
        END IF;

        NEW.status := 'Pending Approval';
        NEW.completion_requested_by := auth.uid();
        NEW.completion_requested_at := now();
        NEW.completion_approved_by := NULL;
        NEW.completion_approved_at := NULL;
        UPDATE public.crm_deals
           SET workflow_status = 'DESIGN_PENDING_APPROVAL',
               stage = 'PITCH',
               design_task_status = 'COMPLETED'
         WHERE id = NEW.crm_deal_id;

        v_submitter_name := COALESCE(public.email_profile_name(auth.uid()), 'MQ-08');
        v_attachment_links := COALESCE(to_jsonb(NEW.submission_links), '[]'::jsonb);

        FOR v_approval IN
            SELECT DISTINCT step.approver_id
              FROM public.crm_design_task_approval_steps step
             WHERE step.task_id = NEW.id
        LOOP
            INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
            VALUES (
                v_approval.approver_id,
                v_submitter_name || ' submitted completed Design files for approval: ' || NEW.title,
                'crm_design_task_approval_requested',
                NEW.id,
                auth.uid(),
                '/?view=approvals',
                jsonb_build_object(
                    'deal_id', NEW.crm_deal_id,
                    'task_title', NEW.title,
                    'submitted_by', v_submitter_name,
                    'attachment_links', v_attachment_links
                )
            ) RETURNING id INTO v_notification_id;

            BEGIN
                INSERT INTO public.task_email_outbox(
                    notification_id, task_id, recipient_id, recipient_email,
                    subject, message, action_url, attachment_links,
                    always_send, context_type, details
                )
                SELECT
                    v_notification_id,
                    NEW.id,
                    profile.id,
                    auth_user.email,
                    'Design approval required: ' || NEW.title,
                    v_submitter_name || ' submitted completed Design files for the CRM deal "' || v_deal.title || '". Review all files and approve or reject the task.',
                    '/?view=approvals',
                    v_attachment_links,
                    true,
                    'CRM_DESIGN_APPROVAL',
                    jsonb_build_object(
                        'deal_id', NEW.crm_deal_id,
                        'deal_title', v_deal.title,
                        'task_title', NEW.title,
                        'submitted_by', v_submitter_name
                    )
                FROM public.profiles profile
                JOIN auth.users auth_user ON auth_user.id = profile.id
                WHERE profile.id = v_approval.approver_id
                  AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Unable to queue CRM Design approval email for %: %', v_approval.approver_id, SQLERRM;
            END;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: enforce_deal_workflow_transition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_deal_workflow_transition() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.stage IN ('PROPOSAL', 'NEGOTIATION', 'WON')
       AND COALESCE(NEW.workflow_status, 'NOT_STARTED') <> 'APPROVED' THEN
        RAISE EXCEPTION 'All internal deal approvals must be completed before this stage';
    END IF;
    IF NEW.stage = 'LOST' AND NULLIF(trim(COALESCE(NEW.lost_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A lost reason is required';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: enforce_executive_admin_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_executive_admin_role() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF public.is_executive_admin_title(NEW.job_title) THEN
        NEW.role := 'ADMIN';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: enforce_marketing_design_review(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_marketing_design_review() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE is_designing boolean;
BEGIN
    -- CRM proposal tasks use the dedicated approval cycle below.
    IF NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN' THEN RETURN NEW; END IF;
    is_designing := NEW.department = 'Marketing' AND NEW.sub_type = 'Designing Task';
    IF NOT is_designing THEN RETURN NEW; END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.delivery_status IS NOT NULL AND NOT public.is_marketing_department_manager(auth.uid()) THEN
            RAISE EXCEPTION 'Only the Marketing department manager can set Delivery Status' USING ERRCODE = '42501';
        END IF;
        NEW.status := CASE WHEN NEW.delivery_status = 'Approved' THEN 'completed' ELSE 'review' END;
        RETURN NEW;
    END IF;
    IF NEW.delivery_status IS DISTINCT FROM OLD.delivery_status
       AND NOT public.is_marketing_department_manager(auth.uid()) THEN
        RAISE EXCEPTION 'Only the Marketing department manager can change Delivery Status' USING ERRCODE = '42501';
    END IF;
    IF NEW.delivery_status IS DISTINCT FROM OLD.delivery_status THEN
        NEW.status := CASE WHEN NEW.delivery_status = 'Approved' THEN 'completed' ELSE 'review' END;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: enforce_mq07_design_assignment_department(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_mq07_design_assignment_department() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    caller_department uuid;
    invalid_assignee uuid;
BEGIN
    IF NOT public.is_mq07_design_list(NEW.task_list_id, auth.uid()) THEN
        RETURN NEW;
    END IF;

    IF NEW.created_by IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'MQ-07 may only create or edit their own Design tasks'
            USING ERRCODE = '42501';
    END IF;

    SELECT department_id INTO caller_department
    FROM public.profiles
    WHERE id = auth.uid() AND emp_index = 7;

    SELECT candidate.id INTO invalid_assignee
    FROM unnest(
        array_remove(
            COALESCE(NEW.assignee_ids, '{}'::uuid[]) || ARRAY[NEW.assignee_id]::uuid[],
            NULL
        )
    ) candidate(id)
    LEFT JOIN public.profiles assignee ON assignee.id = candidate.id
    WHERE assignee.id IS NULL
       OR assignee.is_active IS FALSE
       OR assignee.department_id IS DISTINCT FROM caller_department
    LIMIT 1;

    IF invalid_assignee IS NOT NULL THEN
        RAISE EXCEPTION 'Design tasks may only be assigned to active employees in MQ-07''s department'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: enforce_private_task_list_ownership(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_private_task_list_ownership() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF NEW.task_list_id IS NULL THEN RETURN NEW; END IF;
    IF current_setting('app.crm_design_task_creation', true) = 'on' AND NEW.crm_deal_id IS NOT NULL THEN
        NEW.visibility := 'private';
        RETURN NEW;
    END IF;
    IF NOT public.can_add_task_to_list(NEW.task_list_id, auth.uid()) THEN
        RAISE EXCEPTION 'You cannot add tasks to this task list' USING ERRCODE = '42501';
    END IF;
    NEW.visibility := 'private';
    NEW.visible_to := '{}';
    NEW.supervisor_id := NULL;
    RETURN NEW;
END;
$$;


--
-- Name: enforce_task_completion_approval(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_task_completion_approval() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    -- CRM Design tasks have their own five-person completion approval cycle.
    -- Leave the requested completion intact so the dedicated trigger can
    -- convert it to Pending Approval and create those review steps.
    IF NEW.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'
       AND current_setting('app.crm_design_task_finalize', true) IS DISTINCT FROM 'on' THEN
        RETURN NEW;
    END IF;
    IF NEW.status = 'completed' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'completed') THEN
        IF current_setting('app.crm_design_task_finalize', true) = 'on' AND NEW.crm_deal_id IS NOT NULL THEN
            NEW.completion_approved_by := auth.uid();
            NEW.completion_approved_at := now();
        ELSIF public.is_task_department_manager(NEW.department, auth.uid()) THEN
            NEW.completion_approved_by := auth.uid();
            NEW.completion_approved_at := now();
        ELSE
            NEW.status := 'Pending Approval';
            NEW.completion_requested_by := auth.uid();
            NEW.completion_requested_at := now();
            NEW.completion_approved_by := NULL;
            NEW.completion_approved_at := NULL;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: fetch_assigned_project_todo_context(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fetch_assigned_project_todo_context(p_project_id uuid, p_todo_id uuid DEFAULT NULL::uuid) RETURNS TABLE(project_id uuid, project_name text, todo_id uuid, todo_title text, due_at timestamp with time zone, status text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: finalize_crm_deal_approval(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.finalize_crm_deal_approval(p_deal_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_total integer;
    v_approved integer;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to finalize CRM approval' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
    SELECT count(*), count(*) FILTER (WHERE status = 'APPROVED')
      INTO v_total, v_approved
      FROM public.crm_deal_approval_steps
     WHERE deal_id = p_deal_id;
    IF v_total = 0 OR v_total <> v_approved THEN
        RAISE EXCEPTION 'All CRM approval steps must be approved first' USING ERRCODE = '42501';
    END IF;

    UPDATE public.crm_deals SET stage = 'NEGOTIATION', workflow_status = 'APPROVED' WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, actor_id)
    VALUES (p_deal_id, 'STAGE_CHANGED', v_deal.stage, 'NEGOTIATION', auth.uid());
    RETURN jsonb_build_object('deal_id', p_deal_id, 'from_stage', v_deal.stage, 'to_stage', 'NEGOTIATION', 'actor_id', auth.uid());
END;
$$;


--
-- Name: get_employees_radar(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employees_radar(p_date date DEFAULT CURRENT_DATE) RETURNS TABLE(attendance_id uuid, employee_id uuid, full_name text, clock_in_time timestamp with time zone, clock_out_time timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    WITH latest_attendance AS (
        SELECT DISTINCT ON (record.employee_id)
            record.id AS attendance_id,
            record.employee_id,
            COALESCE(profile.full_name, 'Employee') AS full_name,
            record.clock_in_time,
            record.clock_out_time
        FROM public.attendance record
        JOIN public.profiles profile ON profile.id = record.employee_id
        WHERE public.can_view_employees_radar(auth.uid())
          AND record.date = p_date
          AND record.clock_in_time IS NOT NULL
          AND profile.is_active IS DISTINCT FROM FALSE
        ORDER BY record.employee_id, record.clock_in_time DESC NULLS LAST, record.created_at DESC
    )
    SELECT *
    FROM latest_attendance
    ORDER BY (clock_out_time IS NULL) DESC, COALESCE(clock_out_time, clock_in_time) DESC;
$$;


--
-- Name: get_my_department_supervisors(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_department_supervisors() RETURNS TABLE(id uuid, full_name text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT
        department_head.id,
        COALESCE(NULLIF(BTRIM(department_head.full_name), ''), 'Department Manager')::TEXT
    FROM public.profiles AS employee
    JOIN public.departments AS department
      ON department.id = employee.department_id
    JOIN public.profiles AS department_head
      ON department_head.id = department.head_id
    WHERE employee.id = auth.uid();
$$;


--
-- Name: get_my_request_statuses(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_request_statuses() RETURNS TABLE(source_table text, request_id uuid, request_type text, request_details text, request_status text, current_stage text, current_approver_id uuid, current_approver_name text, rejection_reason text, created_at timestamp with time zone, submitter_name text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  WITH request_source AS (
    SELECT 'requests'::TEXT source_table,request.id request_id,
      COALESCE(request.request_type,'Employee Request')::TEXT request_type,
      CASE
        WHEN lower(COALESCE(request.request_type,'')) LIKE 'loan%' THEN 'Loan amount: '||COALESCE(request.loan_amount::TEXT,'0')||' SAR'
        WHEN request.request_type='Leave Request' THEN COALESCE(request.leave_type,'Leave')||' — '||COALESCE(request.number_of_days::TEXT,'0')||' day(s)'
        ELSE COALESCE(request.leave_type,request.request_type,'Employee Request')
      END::TEXT request_details,
      COALESCE(request.status,'PENDING')::TEXT source_status,request.created_at,
      request.employee_id
    FROM public.requests request WHERE request.employee_id=auth.uid()
    UNION ALL
    SELECT 'leave_requests',request.id,'Leave',
      CASE 
        WHEN request.leave_type = 'Short Leave' THEN 
          COALESCE(request.leave_type,'Leave')||' — '||
          CASE WHEN request.short_leave_duration_minutes = 1440 THEN '1 Day' ELSE COALESCE(request.short_leave_duration_minutes::TEXT, '0')||' minutes' END
        ELSE
          COALESCE(request.leave_type,'Leave')||' — '||COALESCE(EXTRACT(DAY FROM (request.end_date::timestamp - request.start_date::timestamp)) + 1, 0)::TEXT||' day(s)'
      END::TEXT,
      COALESCE(request.status,'PENDING'),request.created_at,
      request.employee_id
    FROM public.leave_requests request WHERE request.employee_id=auth.uid()
    UNION ALL
    SELECT 'document_requests',request.id,'Document',
      COALESCE(request.doc_type,'Document')||' — '||COALESCE(request.purpose,'No purpose provided'),
      COALESCE(request.status,'PENDING'),request.created_at,
      request.employee_id
    FROM public.document_requests request WHERE request.employee_id=auth.uid()
    UNION ALL
    SELECT 'expenses',request.id,'Expense',
      COALESCE(request.amount::TEXT,'0')||' SAR — '||COALESCE(request.description,'No description'),
      COALESCE(request.status,'PENDING'),request.created_at,
      request.employee_id
    FROM public.expenses request WHERE request.employee_id=auth.uid()
  )
  SELECT source.source_table,source.request_id,source.request_type,source.request_details,
    COALESCE(workflow.status,upper(source.source_status))::TEXT request_status,
    step.stage_key::TEXT current_stage,step.approver_id,
    COALESCE(approver.full_name,'Management')::TEXT current_approver_name,
    COALESCE(step.decision_note,'')::TEXT rejection_reason,
    source.created_at,
    COALESCE(submitter.full_name, 'Unknown')::TEXT submitter_name
  FROM request_source source
  LEFT JOIN public.profiles submitter ON submitter.id=source.employee_id
  LEFT JOIN public.request_approval_workflows workflow
    ON workflow.source_table=source.source_table AND workflow.source_id=source.request_id
  LEFT JOIN public.request_approval_steps step
    ON step.workflow_id=workflow.id AND step.step_order=workflow.current_step
  LEFT JOIN public.profiles approver ON approver.id=step.approver_id
  ORDER BY source.created_at DESC;
$$;


--
-- Name: get_project_detail_secure(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_project_detail_secure(p_project_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_user UUID := auth.uid(); v_project public.projects%ROWTYPE; v_can_financial BOOLEAN; v_project_json JSONB;
BEGIN
    IF v_user IS NULL OR NOT public.can_access_project(p_project_id, v_user) THEN RAISE EXCEPTION 'Project not found or access denied' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_project FROM public.projects WHERE id=p_project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE='P0002'; END IF;
    v_can_financial := public.can_view_business_financials(v_user);
    v_project_json := to_jsonb(v_project) || jsonb_build_object(
        'project_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.project_amount) ELSE 'null'::JSONB END,
        'paid_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.paid_amount) ELSE 'null'::JSONB END,
        'budget_amount', CASE WHEN v_can_financial THEN to_jsonb(v_project.budget_amount) ELSE 'null'::JSONB END,
        'actual_cost', CASE WHEN v_can_financial THEN to_jsonb(v_project.actual_cost) ELSE 'null'::JSONB END
    );
    RETURN jsonb_build_object(
        'project', v_project_json,
        'updates', COALESCE((SELECT jsonb_agg(item) FROM public.list_project_updates_secure(p_project_id) item), '[]'::JSONB),
        'todos', COALESCE((SELECT jsonb_agg(item) FROM public.list_project_todos_secure(p_project_id) item), '[]'::JSONB),
        'attachments', COALESCE((SELECT jsonb_agg(to_jsonb(item)) FROM public.list_project_shared_attachments(p_project_id) item), '[]'::JSONB)
    );
END;
$$;


--
-- Name: get_request_filter_directory(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_request_filter_directory() RETURNS TABLE(employee_id uuid, full_name text, email text, department_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'pg_temp'
    AS $$
  SELECT profile.id,COALESCE(profile.full_name,'Unknown User'),COALESCE(account.email::TEXT,''),profile.department_id
  FROM public.profiles profile
  LEFT JOIN auth.users account ON account.id=profile.id
  WHERE profile.is_active=TRUE
    AND (
      profile.id=auth.uid()
      OR public.is_system_admin(auth.uid())
      OR public.is_department_manager_for(auth.uid(),profile.id)
    )
  ORDER BY profile.full_name;
$$;


--
-- Name: get_task_employee_access_grants(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_task_employee_access_grants() RETURNS TABLE(viewer_id uuid, subject_id uuid, granted_by uuid, created_at timestamp with time zone, is_locked boolean)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: get_task_list_department_directory(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_task_list_department_directory() RETURNS TABLE(id uuid, full_name text, display_name_ar text, role text, department_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT member.id, member.full_name::text, member.display_name_ar::text,
         member.role::text, member.department_id
  FROM public.profiles viewer
  JOIN public.profiles member ON member.department_id = viewer.department_id
  WHERE viewer.id = auth.uid()
    AND member.is_active IS DISTINCT FROM false
  ORDER BY member.full_name;
$$;


--
-- Name: get_task_secure(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_task_secure(p_task_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT item FROM public.list_accessible_tasks_secure() item
  WHERE item->>'id' = p_task_id::text LIMIT 1;
$$;


--
-- Name: get_task_watcher_directory(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_task_watcher_directory() RETURNS TABLE(id uuid, full_name text, display_name_ar text, role text, department_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT profile.id, profile.full_name::text, profile.display_name_ar::text,
         profile.role::text, profile.department_id
  FROM public.profiles profile
  WHERE profile.is_active IS DISTINCT FROM false
  ORDER BY profile.full_name;
$$;


--
-- Name: get_user_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_role() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  user_role text;
BEGIN
  SELECT role INTO user_role FROM public.profiles WHERE id = auth.uid();
  RETURN user_role;
END;
$$;


--
-- Name: import_departments_job_titles(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.import_departments_job_titles(payload jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
DECLARE
    item JSONB;
    v_dept_name TEXT;
    v_dept_name_ar TEXT;
    v_job_name TEXT;
    v_job_name_ar TEXT;
    v_head_val TEXT;
    v_head_id UUID;
    v_dept_id UUID;
    v_job_id UUID;
    v_dept_created INTEGER := 0;
    v_dept_updated INTEGER := 0;
    v_job_created INTEGER := 0;
    v_job_updated INTEGER := 0;
BEGIN
    -- Basic auth check
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND UPPER(COALESCE(role, '')) = 'ADMIN') THEN
        RETURN jsonb_build_object('success', FALSE, 'error', 'Unauthorized');
    END IF;

    FOR item IN SELECT * FROM jsonb_array_elements(payload)
    LOOP
        v_dept_name := trim(item->>'dept_en');
        v_dept_name_ar := trim(item->>'dept_ar');
        v_job_name := trim(item->>'job_en');
        v_job_name_ar := trim(item->>'job_ar');
        v_head_val := trim(item->>'head');
        
        -- Process Department
        IF v_dept_name IS NOT NULL AND v_dept_name <> '' THEN
            SELECT id INTO v_dept_id FROM public.departments WHERE LOWER(name) = LOWER(v_dept_name) LIMIT 1;
            

            -- Resolve head_id from employee_id or email
            v_head_id := NULL;
            IF v_head_val IS NOT NULL AND v_head_val <> '' THEN
                SELECT id INTO v_head_id FROM public.profiles WHERE employee_id = v_head_val OR email = v_head_val LIMIT 1;
            END IF;

            IF v_dept_id IS NULL THEN
                INSERT INTO public.departments (name, name_ar, head_id, is_active)
                VALUES (v_dept_name, v_dept_name_ar, v_head_id, true)
                RETURNING id INTO v_dept_id;
                v_dept_created := v_dept_created + 1;
            ELSE
                UPDATE public.departments SET 
                    name_ar = COALESCE(NULLIF(v_dept_name_ar, ''), name_ar),
                    head_id = COALESCE(v_head_id, head_id)
                WHERE id = v_dept_id;
                v_dept_updated := v_dept_updated + 1;
            END IF;

            
            -- Process Job Title
            IF v_job_name IS NOT NULL AND v_job_name <> '' THEN
                SELECT id INTO v_job_id FROM public.job_titles WHERE LOWER(name) = LOWER(v_job_name) AND department_id = v_dept_id LIMIT 1;
                
                IF v_job_id IS NULL THEN
                    INSERT INTO public.job_titles (name, name_ar, department_id, is_active)
                    VALUES (v_job_name, v_job_name_ar, v_dept_id, true);
                    v_job_created := v_job_created + 1;
                ELSE
                    IF v_job_name_ar IS NOT NULL AND v_job_name_ar <> '' THEN
                        UPDATE public.job_titles SET name_ar = v_job_name_ar WHERE id = v_job_id;
                        v_job_updated := v_job_updated + 1;
                    END IF;
                END IF;
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'departments_created', v_dept_created,
        'departments_updated', v_dept_updated,
        'jobs_created', v_job_created,
        'jobs_updated', v_job_updated
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', FALSE, 'error', SQLERRM);
END; $$;


--
-- Name: inherit_parent_task_access(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inherit_parent_task_access() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    parent_row public.tasks%ROWTYPE;
BEGIN
    IF NEW.parent_task_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.id IS NOT NULL AND NEW.parent_task_id = NEW.id THEN
        RAISE EXCEPTION 'A task cannot be its own parent' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO parent_row FROM public.tasks WHERE id = NEW.parent_task_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Parent task does not exist' USING ERRCODE = '23503';
    END IF;
    IF NOT public.can_view_task(parent_row.id, COALESCE(auth.uid(), NEW.created_by)) THEN
        RAISE EXCEPTION 'You cannot add a subtask to this task' USING ERRCODE = '42501';
    END IF;
    NEW.project_id := parent_row.project_id;
    NEW.visibility := parent_row.visibility;
    NEW.visible_to := COALESCE(parent_row.visible_to, '{}');
    NEW.watchers := COALESCE(parent_row.watchers, '{}');
    NEW.supervisor_id := parent_row.supervisor_id;
    RETURN NEW;
END;
$$;


--
-- Name: is_crm_approval_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_crm_approval_admin(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g')))
              IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
    );
$$;


--
-- Name: is_department_manager_for(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_department_manager_for(p_viewer_id uuid, p_employee_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles viewer
    JOIN public.profiles employee ON employee.id=p_employee_id
    WHERE viewer.id=p_viewer_id
      AND viewer.department_id IS NOT NULL
      AND viewer.department_id=employee.department_id
      AND upper(COALESCE(viewer.role,'')) IN ('MANAGER','SUPERVISOR')
  );
$$;


--
-- Name: is_employee_request_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_employee_request_admin(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = p_user_id AND profile.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) IN
                 ('GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER', 'MARKETING MANAGER')
              OR UPPER(COALESCE(profile.employee_id,'')) IN ('MQ-04', 'MQ-05')
          )
    );
$$;


--
-- Name: is_executive_admin_title(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_executive_admin_title(candidate_title text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT UPPER(BTRIM(REGEXP_REPLACE(COALESCE(candidate_title, ''), '[_-]+', ' ', 'g')))
        IN ('GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER');
$$;


--
-- Name: is_ines_modani_profile(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_ines_modani_profile(p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: is_ines_modani_task(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_ines_modani_task(p_task_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: is_ines_modani_task_list(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_ines_modani_task_list(p_list_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.tasks task
        WHERE task.task_list_id = p_list_id
          AND public.is_ines_modani_task(task.id)
    );
$$;


--
-- Name: is_marketing_department_manager(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_marketing_department_manager(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.departments department
        WHERE department.name = 'Marketing'
          AND department.head_id = p_user_id
    );
$$;


--
-- Name: is_marketing_managed_task_list(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_marketing_managed_task_list(p_list_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.task_lists list
        WHERE list.id = p_list_id
          AND COALESCE(list.name, '') ~* '(design|marketing|sales|تصميم|تسويق|مبيعات)'
    );
$$;


--
-- Name: is_marketing_task_manager(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_marketing_task_manager(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: is_mq07_design_list(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_mq07_design_list(p_list_id uuid, p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        JOIN public.task_lists list
          ON list.id = p_list_id
         AND list.department_id = profile.department_id
        WHERE profile.id = p_user_id
          AND profile.emp_index = 7
          AND profile.is_active IS DISTINCT FROM false
          AND COALESCE(list.name, '') ~* '(design|تصميم)'
    );
$$;


--
-- Name: is_mq20_profile(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_mq20_profile(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND UPPER(BTRIM(COALESCE(profile.employee_id, ''))) = 'MQ-20'
          AND profile.is_active IS DISTINCT FROM false
    );
$$;


--
-- Name: is_project_portfolio_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_project_portfolio_admin(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles profile
        WHERE profile.id = p_user_id
          AND profile.is_active IS DISTINCT FROM FALSE
          AND (
              UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.role, ''), '[_-]+', ' ', 'g'))) IN (
                  'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN',
                  'MANAGER', 'SUPERVISOR', 'GM', 'GENERAL MANAGER',
                  'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'
              )
              OR UPPER(BTRIM(REGEXP_REPLACE(COALESCE(profile.job_title, ''), '[_-]+', ' ', 'g'))) ~
                 '(^| )(MANAGER|SUPERVISOR|GM|GENERAL MANAGER|CEO|CHIEF EXECUTIVE|CHIEF EXECUTIVE OFFICER)( |$)'
              OR BTRIM(COALESCE(profile.job_title_ar, '')) ~ '(مدير|مشرف)'
          )
    );
$_$;


--
-- Name: is_project_todo_assignee_eligible(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_project_todo_assignee_eligible(p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: is_request_workflow_approver(text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_request_workflow_approver(p_source_table text, p_source_id uuid, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS(
        SELECT 1 FROM public.request_approval_workflows w
        JOIN public.request_approval_steps s ON s.workflow_id=w.id
        WHERE w.source_table=p_source_table AND w.source_id=p_source_id AND s.approver_id=p_user_id
    );
$$;


--
-- Name: is_sales_marketing_employee(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_sales_marketing_employee(p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: is_system_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_system_admin(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles profile
    WHERE profile.id=p_user_id
      AND upper(COALESCE(profile.role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
  );
$$;


--
-- Name: is_task_admin(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_task_admin(p_user_id uuid DEFAULT auth.uid()) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = p_user_id
          AND upper(COALESCE(p.role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN')
    );
$$;


--
-- Name: is_valid_attendance_coordinates(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_valid_attendance_coordinates(candidate text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
    latitude NUMERIC;
    longitude NUMERIC;
BEGIN
    IF BTRIM(COALESCE(candidate, '')) !~ '^-?[0-9]+(?:\.[0-9]+)?\s*,\s*-?[0-9]+(?:\.[0-9]+)?$' THEN
        RETURN FALSE;
    END IF;
    latitude := BTRIM(SPLIT_PART(candidate, ',', 1))::NUMERIC;
    longitude := BTRIM(SPLIT_PART(candidate, ',', 2))::NUMERIC;
    RETURN latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180;
EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
END;
$_$;


--
-- Name: is_valid_google_maps_location(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_valid_google_maps_location(candidate text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public', 'pg_temp'
    AS $_$
    SELECT BTRIM(COALESCE(candidate, '')) ~* '^https?://((www\.)?maps\.app\.goo\.gl|((www\.)?goo\.gl/maps)|maps\.google\.[a-z.]+|(([a-z0-9-]+\.)?google\.[a-z.]+/maps))([/?#]|$)';
$_$;


--
-- Name: list_accessible_project_profiles(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_accessible_project_profiles() RETURNS TABLE(id uuid, emp_index integer, full_name text, display_name_ar text, role text, avatar_url text, job_title text, job_title_ar text, department_id uuid, manager_id uuid, is_active boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication is required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT DISTINCT
        profile.id,
        profile.emp_index,
        profile.full_name::TEXT,
        profile.display_name_ar::TEXT,
        profile.role::TEXT,
        profile.avatar_url::TEXT,
        profile.job_title::TEXT,
        profile.job_title_ar::TEXT,
        profile.department_id,
        profile.manager_id,
        profile.is_active
    FROM public.profiles profile
    WHERE profile.is_active IS DISTINCT FROM FALSE
      AND (
          public.is_project_portfolio_admin(auth.uid())
          OR EXISTS (
              SELECT 1
              FROM public.projects project
              WHERE public.can_access_project(project.id, auth.uid())
                AND (
                    profile.id = project.created_by
                    OR profile.id = project.project_manager_id
                    OR profile.id = ANY(COALESCE(project.assigned_people, ARRAY[]::UUID[]))
                )
          )
      )
    ORDER BY profile.emp_index NULLS LAST, profile.full_name;
END;
$$;


--
-- Name: list_accessible_projects_secure(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_accessible_projects_secure() RETURNS SETOF jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: list_accessible_tasks_secure(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_accessible_tasks_secure() RETURNS SETOF jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: list_active_project_assignment_employees(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_active_project_assignment_employees() RETURNS TABLE(id uuid, emp_index integer, full_name text, display_name_ar text, role text, avatar_url text, job_title text, job_title_ar text, department_id uuid, manager_id uuid, is_active boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'CRM access is required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        profile.id,
        profile.emp_index,
        profile.full_name::TEXT,
        profile.display_name_ar::TEXT,
        profile.role::TEXT,
        profile.avatar_url::TEXT,
        profile.job_title::TEXT,
        profile.job_title_ar::TEXT,
        profile.department_id,
        profile.manager_id,
        profile.is_active
    FROM public.profiles profile
    WHERE profile.is_active IS DISTINCT FROM FALSE
    ORDER BY profile.emp_index NULLS LAST, profile.full_name;
END;
$$;


--
-- Name: list_crm_deals_secure(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_crm_deals_secure() RETURNS SETOF jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: list_project_shared_attachments(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_project_shared_attachments(p_project_id uuid) RETURNS TABLE(attachment_type text, attachment_id uuid, source_id uuid, category text, file_name text, file_url text, file_type text, description text, created_at timestamp with time zone, visible_to_project_assignee boolean)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: list_project_todos_secure(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_project_todos_secure(p_project_id uuid) RETURNS SETOF jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT to_jsonb(todo_row)
    FROM public.project_todos todo_row
    WHERE todo_row.project_id=p_project_id AND public.can_access_project(p_project_id, auth.uid())
    ORDER BY todo_row.status DESC, todo_row.due_at ASC;
$$;


--
-- Name: list_project_updates_secure(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_project_updates_secure(p_project_id uuid) RETURNS SETOF jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT to_jsonb(update_row) || jsonb_build_object('author', CASE WHEN profile.id IS NULL THEN NULL ELSE jsonb_build_object('id', profile.id, 'full_name', profile.full_name, 'display_name_ar', profile.display_name_ar, 'emp_index', profile.emp_index) END)
    FROM public.project_updates update_row
    LEFT JOIN public.profiles profile ON profile.id=update_row.author_id
    WHERE update_row.project_id=p_project_id AND public.can_access_project(p_project_id, auth.uid())
    ORDER BY update_row.created_at DESC;
$$;


--
-- Name: task_activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_activity (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    task_id uuid NOT NULL,
    actor_id uuid,
    action text NOT NULL,
    from_status text,
    to_status text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: list_task_activity_secure(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_task_activity_secure(p_task_id uuid) RETURNS SETOF public.task_activity
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT * FROM public.task_activity WHERE task_id = p_task_id
    AND auth.uid() IS NOT NULL AND public.can_access_task(p_task_id, auth.uid())
  ORDER BY created_at DESC;
$$;


--
-- Name: list_task_attachments_secure(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_task_attachments_secure(p_task_id uuid, p_scope text DEFAULT NULL::text) RETURNS SETOF jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: list_task_comments_secure(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.list_task_comments_secure(p_task_id uuid) RETURNS SETOF public.task_comments
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT * FROM public.task_comments
  WHERE task_id = p_task_id AND auth.uid() IS NOT NULL AND public.can_access_task(p_task_id, auth.uid())
  ORDER BY created_at ASC;
$$;


--
-- Name: mark_crm_deal_lost(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_crm_deal_lost(p_deal_id uuid, p_reason text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_reason text := NULLIF(BTRIM(COALESCE(p_reason, '')), '');
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to update CRM deals' USING ERRCODE = '42501';
    END IF;
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'A reason for loss is required' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002';
    END IF;
    IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN
        RAISE EXCEPTION 'This deal is already lost' USING ERRCODE = '42501';
    END IF;

    UPDATE public.crm_deals
       SET stage = 'LOST', lost_reason = v_reason
     WHERE id = v_deal.id;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (v_deal.id, 'DEAL_LOST', v_deal.stage, 'LOST', v_reason, auth.uid());

    RETURN jsonb_build_object(
        'deal_id', v_deal.id,
        'from_stage', v_deal.stage,
        'to_stage', 'LOST',
        'reason', v_reason,
        'actor_id', auth.uid()
    );
END;
$$;


--
-- Name: notify_project_todo_assignees(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_project_todo_assignees() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    recipient_id UUID;
    recipient_email TEXT;
    notification_row public.notifications%ROWTYPE;
    project_name TEXT;
    actor_name TEXT;
    action_path TEXT;
    notification_message TEXT;
    email_details JSONB;
BEGIN
    SELECT COALESCE(NULLIF(BTRIM(project.project_name), ''), 'Project')
    INTO project_name
    FROM public.projects project
    WHERE project.id = NEW.project_id;

    SELECT COALESCE(
        NULLIF(BTRIM(profile.full_name), ''),
        NULLIF(BTRIM(profile.display_name), ''),
        NULLIF(BTRIM(profile.display_name_ar), ''),
        'Project manager'
    )
    INTO actor_name
    FROM public.profiles profile
    WHERE profile.id = NEW.created_by;

    project_name := COALESCE(project_name, 'Project');
    actor_name := COALESCE(actor_name, 'Project manager');
    action_path := FORMAT('/?view=projects&project=%s&todo=%s', NEW.project_id, NEW.id);
    notification_message := FORMAT('%s assigned you the project To-Do "%s" in "%s".', actor_name, NEW.title, project_name);
    email_details := JSONB_BUILD_OBJECT(
        'Project', project_name,
        'To-Do item', NEW.title,
        'Assigned by', actor_name,
        'Due date and time', TO_CHAR(NEW.due_at AT TIME ZONE 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI')
    );

    FOREACH recipient_id IN ARRAY NEW.assignee_ids LOOP
        INSERT INTO public.notifications(
            user_id,
            message,
            event_type,
            actor_id,
            action_url,
            metadata
        )
        VALUES (
            recipient_id,
            notification_message,
            'project_todo_assigned',
            NEW.created_by,
            action_path,
            JSONB_BUILD_OBJECT(
                'project_id', NEW.project_id,
                'project_name', project_name,
                'project_todo_id', NEW.id,
                'project_todo_title', NEW.title,
                'due_at', NEW.due_at,
                'actor_name', actor_name
            )
        )
        RETURNING * INTO notification_row;

        SELECT auth_user.email
        INTO recipient_email
        FROM auth.users auth_user
        WHERE auth_user.id = recipient_id;

        IF NULLIF(BTRIM(recipient_email), '') IS NOT NULL THEN
            INSERT INTO public.task_email_outbox(
                notification_id,
                task_id,
                recipient_id,
                recipient_email,
                subject,
                message,
                action_url,
                always_send,
                context_type,
                details
            )
            VALUES (
                notification_row.id,
                NULL,
                recipient_id,
                recipient_email,
                FORMAT('Project To-Do assigned: %s', NEW.title),
                notification_message,
                action_path,
                TRUE,
                'PROJECT_TODO',
                email_details
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;


--
-- Name: notify_task_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_task_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM public.queue_task_notification(
            NEW.id, NEW.created_by,
            CASE WHEN NEW.parent_task_id IS NULL THEN 'task_created' ELSE 'subtask_created' END,
            CASE WHEN NEW.parent_task_id IS NULL THEN 'New task: ' ELSE 'New subtask: ' END || NEW.title
        );
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), CASE WHEN NEW.status = 'Pending Approval' THEN 'task_approval_requested' ELSE 'task_status_changed' END,
            CASE WHEN NEW.status = 'Pending Approval' THEN 'Completion approval requested for "' || NEW.title || '"'
            ELSE 'Task "' || NEW.title || '" moved ' ||
            CASE
                WHEN (CASE NEW.status WHEN 'todo' THEN 1 WHEN 'in_progress' THEN 2 WHEN 'review' THEN 3 WHEN 'completed' THEN 4 ELSE 0 END)
                   >= (CASE OLD.status WHEN 'todo' THEN 1 WHEN 'in_progress' THEN 2 WHEN 'review' THEN 3 WHEN 'completed' THEN 4 ELSE 0 END)
                THEN 'forward' ELSE 'backward'
            END || ' from ' || OLD.status || ' to ' || NEW.status END);
    ELSIF NEW.assignee_id IS DISTINCT FROM OLD.assignee_id THEN
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), 'task_assigned',
            'Task assigned: ' || NEW.title);
    ELSE
        PERFORM public.queue_task_notification(NEW.id, auth.uid(), 'task_updated',
            'Task updated: ' || NEW.title);
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: notify_task_comment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_task_comment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'queue_task_notification') THEN
        PERFORM public.queue_task_notification(
            NEW.task_id,
            NEW.user_id,
            'task_comment',
            'New comment on task'
        );
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: protect_employee_document_system_fields(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_employee_document_system_fields() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND
       (to_jsonb(NEW) - ARRAY[
           'doc_name',
           'owner_name',
           'owner_email',
           'responsible_name',
           'responsible_email',
           'expiration_date',
           'owner_phone'
       ]::TEXT[])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY[
           'doc_name',
           'owner_name',
           'owner_email',
           'responsible_name',
           'responsible_email',
           'expiration_date',
           'owner_phone'
       ]::TEXT[]) THEN
        RAISE EXCEPTION 'System-managed document fields cannot be changed from the app'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: protect_lost_crm_deal_edits(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_lost_crm_deal_edits() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: protect_profile_privileged_fields(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_profile_privileged_fields() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    caller_role TEXT;
    caller_job_title TEXT;
    employee_editable_fields TEXT[] := ARRAY[
        'full_name','display_name','iqama_number','phone_number','avatar_url','last_login','birth_date'
    ];
    hr_editable_fields TEXT[] := ARRAY[
        'full_name','display_name','iqama_number','phone_number','avatar_url','last_login','birth_date',
        'job_title','department_id','base_salary','nationality','role'
    ];
BEGIN
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    SELECT UPPER(COALESCE(role, '')), UPPER(COALESCE(job_title, ''))
      INTO caller_role, caller_job_title
      FROM public.profiles
     WHERE id = auth.uid();

    IF caller_role IN ('ADMIN', 'ROLE_SYSTEM_ADMIN') THEN RETURN NEW; END IF;

    IF caller_job_title = 'HR MANAGER' THEN
        IF (to_jsonb(NEW) - hr_editable_fields) IS DISTINCT FROM (to_jsonb(OLD) - hr_editable_fields) THEN
            RAISE EXCEPTION 'HR Manager can only change contract-synchronized employment fields' USING ERRCODE = '42501';
        END IF;
        RETURN NEW;
    END IF;

    IF (to_jsonb(NEW) - employee_editable_fields) IS DISTINCT FROM (to_jsonb(OLD) - employee_editable_fields) THEN
        RAISE EXCEPTION 'Only an administrator can change protected profile fields' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: protect_task_access_fields(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_task_access_fields() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF auth.uid() IS NULL OR public.is_task_admin(auth.uid()) THEN RETURN NEW; END IF;
    IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
        RAISE EXCEPTION 'The task creator cannot be changed' USING ERRCODE = '42501';
    END IF;
    IF auth.uid() <> OLD.created_by AND (
        NEW.assignee_id IS DISTINCT FROM OLD.assignee_id
        OR NEW.supervisor_id IS DISTINCT FROM OLD.supervisor_id
        OR NEW.project_id IS DISTINCT FROM OLD.project_id
        OR NEW.parent_task_id IS DISTINCT FROM OLD.parent_task_id
        OR NEW.visibility IS DISTINCT FROM OLD.visibility
        OR NEW.visible_to IS DISTINCT FROM OLD.visible_to
        OR NEW.watchers IS DISTINCT FROM OLD.watchers
    ) THEN
        RAISE EXCEPTION 'Only the task creator can change task access' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: queue_request_notification(uuid, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_request_notification(p_user_id uuid, p_message text, p_event_type text, p_workflow_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
    notification_row public.notifications%ROWTYPE;
    workflow_row public.request_approval_workflows%ROWTYPE;
    source_details JSONB := '{}'::JSONB;
    email_details JSONB;
    actor_id UUID := auth.uid();
    v_attachment_links JSONB := '[]'::JSONB;
BEGIN
    SELECT * INTO workflow_row FROM public.request_approval_workflows WHERE id = p_workflow_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF workflow_row.source_table IN ('requests', 'leave_requests', 'document_requests', 'expenses') THEN
        EXECUTE format('SELECT to_jsonb(source_row) FROM public.%I source_row WHERE id = $1', workflow_row.source_table)
        INTO source_details USING workflow_row.source_id;
    END IF;

    -- Extract expense receipt if available
    IF workflow_row.source_table = 'expenses' THEN
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'url', receipt_base64,
                    'name', 'Receipt - ' || COALESCE(description, 'Expense')
                )
            ),
            '[]'::JSONB
        )
        INTO v_attachment_links
        FROM public.expenses
        WHERE id = workflow_row.source_id AND receipt_base64 IS NOT NULL AND BTRIM(receipt_base64) <> '';
    END IF;

    source_details := COALESCE(source_details, '{}'::JSONB)
        - 'id' - 'employee_id' - 'is_archived' - 'receipt_base64' - 'attachment_base64' - 'file_data';

    email_details := jsonb_strip_nulls(jsonb_build_object(
        'Request type', workflow_row.request_type,
        'Employee', public.email_profile_name(workflow_row.employee_id),
        'Action by', public.email_profile_name(actor_id),
        'Approval status', workflow_row.status,
        'Current approval step', workflow_row.current_step,
        'Event', p_event_type,
        'Request details', source_details
    ));

    INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
    VALUES (
        p_user_id, p_message, p_event_type, actor_id, '/?view=requests&request=' || workflow_row.source_id,
        jsonb_build_object(
            'workflow_id', p_workflow_id,
            'request_type', workflow_row.request_type,
            'source_table', workflow_row.source_table,
            'source_id', workflow_row.source_id,
            'employee_name', public.email_profile_name(workflow_row.employee_id),
            'actor_name', public.email_profile_name(actor_id),
            'attachment_links', v_attachment_links
        )
    ) RETURNING * INTO notification_row;

    BEGIN
        INSERT INTO public.task_email_outbox(
            notification_id, task_id, recipient_id, recipient_email, subject, message,
            action_url, attachment_links, always_send, context_type, details
        )
        SELECT notification_row.id, NULL, profile.id, auth_user.email,
               'Employee request update: ' || workflow_row.request_type,
               p_message, notification_row.action_url, v_attachment_links, TRUE, 'EMPLOYEE_REQUEST', email_details
        FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE profile.id = p_user_id
          AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Unable to queue employee request email: %', SQLERRM;
    END;
END;
$_$;


--
-- Name: queue_task_notification(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_task_notification(p_task_id uuid, p_actor_id uuid, p_event_type text, p_message text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
    task_row public.tasks%ROWTYPE;
    recipient UUID;
    notification_row public.notifications%ROWTYPE;
    latest_comment TEXT;
    attachment_links JSONB := '[]'::JSONB;
    db_file_links JSONB := '[]'::JSONB;
    task_details JSONB;
BEGIN
    SELECT * INTO task_row FROM public.tasks WHERE id = p_task_id;
    IF NOT FOUND THEN RETURN; END IF;

    IF p_event_type = 'task_comment' THEN
        IF to_regclass('public.task_comments') IS NOT NULL THEN
            SELECT content INTO latest_comment
            FROM public.task_comments
            WHERE task_id = p_task_id AND user_id = p_actor_id
            ORDER BY created_at DESC LIMIT 1;

            SELECT COALESCE(jsonb_agg(
                CASE 
                    WHEN jsonb_typeof(elem) = 'object' AND elem ? 'url' THEN elem->>'url'
                    WHEN jsonb_typeof(elem) = 'object' AND elem ? 'file_url' THEN elem->>'file_url'
                    ELSE elem #>> '{}'
                END
            ) FILTER (WHERE elem IS NOT NULL), '[]'::JSONB)
            INTO db_file_links
            FROM (
                SELECT elem
                FROM public.task_comments tc,
                     jsonb_array_elements(COALESCE(tc.attachments, '[]'::JSONB)) elem
                WHERE tc.task_id = p_task_id AND tc.user_id = p_actor_id
                ORDER BY tc.created_at DESC LIMIT 1
            ) sub;
        END IF;
    END IF;

    -- Safely read task_attachments if table exists
    IF to_regclass('public.task_attachments') IS NOT NULL THEN
        EXECUTE 'SELECT COALESCE(jsonb_agg(file_url) FILTER (WHERE file_url IS NOT NULL AND BTRIM(file_url) <> ''''), ''[]''::JSONB) FROM public.task_attachments WHERE task_id = $1'
        INTO db_file_links
        USING p_task_id;
    END IF;
    db_file_links := COALESCE(db_file_links, '[]'::JSONB);

    -- Aggregate all content links, submission links, uploaded files, and source links
    SELECT COALESCE(jsonb_agg(DISTINCT link) FILTER (WHERE link IS NOT NULL AND BTRIM(link) <> ''), '[]'::JSONB)
    INTO attachment_links
    FROM (
        SELECT jsonb_array_elements_text(COALESCE(to_jsonb(task_row.content_links), '[]'::JSONB)) AS link
        UNION ALL
        SELECT jsonb_array_elements_text(COALESCE(to_jsonb(task_row.submission_links), '[]'::JSONB)) AS link
        UNION ALL
        SELECT task_row.upload_link AS link WHERE task_row.upload_link IS NOT NULL
        UNION ALL
        SELECT task_row.source_link AS link WHERE task_row.source_link IS NOT NULL
        UNION ALL
        SELECT jsonb_array_elements_text(db_file_links) AS link
        UNION ALL
        SELECT jsonb_array_elements_text(
            CASE 
                WHEN jsonb_typeof(COALESCE(to_jsonb(task_row.attachments), '[]'::JSONB)) = 'array' 
                THEN to_jsonb(task_row.attachments) 
                ELSE '[]'::JSONB 
            END
        ) AS link
    ) task_links;

    task_details := jsonb_strip_nulls(jsonb_build_object(
        'Task title', task_row.title,
        'Description', task_row.description,
        'Task creator', public.email_profile_name(task_row.created_by),
        'Updated by', public.email_profile_name(p_actor_id),
        'Assigned to', public.email_profile_name(task_row.assignee_id),
        'Supervisor', public.email_profile_name(task_row.supervisor_id),
        'Status', task_row.status,
        'Priority', task_row.priority,
        'Department', task_row.department,
        'Category', task_row.category,
        'Start date', task_row.start_date,
        'Due date', COALESCE(task_row.due_date, task_row.end_date),
        'Estimated time', task_row.estimated_time,
        'Event', p_event_type,
        'Comment', latest_comment
    ));

    FOR recipient IN
        SELECT DISTINCT recipient_id FROM (
            SELECT unnest(array_remove(ARRAY[task_row.created_by, task_row.assignee_id, task_row.supervisor_id], NULL)) AS recipient_id
            UNION SELECT unnest(COALESCE(task_row.watchers, '{}'))
            UNION SELECT unnest(COALESCE(task_row.visible_to, '{}'))
            UNION SELECT department.head_id FROM public.departments department
                WHERE department.name = task_row.department AND department.head_id IS NOT NULL
            UNION SELECT unnest(COALESCE(project.assigned_people, '{}')) FROM public.projects project WHERE project.id = task_row.project_id
            UNION SELECT user_id FROM public.task_comments WHERE task_id = p_task_id
            UNION SELECT profile.id FROM public.profiles profile
                WHERE UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
        ) recipients
        WHERE recipient_id IS DISTINCT FROM p_actor_id
           OR EXISTS (
               SELECT 1 FROM public.profiles administrator
               WHERE administrator.id = recipient_id
                 AND UPPER(REPLACE(COALESCE(administrator.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
           )
    LOOP
        INSERT INTO public.notifications(user_id, message, event_type, task_id, actor_id, action_url, metadata)
        VALUES (
            recipient, p_message, p_event_type, p_task_id, p_actor_id,
            '/?view=tasks&task=' || p_task_id,
            jsonb_build_object(
                'task_title', task_row.title,
                'parent_task_id', task_row.parent_task_id,
                'department_manager_id', (SELECT head_id FROM public.departments WHERE name = task_row.department LIMIT 1),
                'comment_text', latest_comment,
                'attachment_links', attachment_links,
                'notify_via_email', task_row.notify_via_email,
                'actor_name', public.email_profile_name(p_actor_id),
                'creator_name', public.email_profile_name(task_row.created_by)
            )
        ) RETURNING * INTO notification_row;

        BEGIN
            INSERT INTO public.task_email_outbox(
                notification_id, task_id, recipient_id, recipient_email, subject, message,
                action_url, comment_text, attachment_links, always_send, context_type, details
            )
            SELECT notification_row.id, task_row.id, profile.id, auth_user.email,
                   CASE WHEN p_event_type = 'task_comment' THEN 'New comment: ' ELSE 'Task update: ' END || task_row.title,
                   p_message, notification_row.action_url, latest_comment, attachment_links,
                   UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'),
                   'TASK', task_details
            FROM public.profiles profile JOIN auth.users auth_user ON auth_user.id = profile.id
            WHERE profile.id = recipient
              AND (
                  UPPER(REPLACE(COALESCE(profile.role, ''), '_', ' ')) IN ('ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN')
                  OR (task_row.notify_via_email IS TRUE AND profile.task_email_notifications = TRUE)
              )
              AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Unable to queue detailed task email for recipient %: %', recipient, SQLERRM;
        END;
    END LOOP;
END;
$_$;


--
-- Name: queue_task_status_notification(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.queue_task_status_notification() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    recipient UUID;
    notification_row public.notifications%ROWTYPE;
    actor_name TEXT := COALESCE(public.email_profile_name(auth.uid()), 'System');
    status_label TEXT := COALESCE(NULLIF(BTRIM(NEW.status), ''), 'Unknown');
    task_message TEXT;
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status OR auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    task_message := format('Task "%s" status changed to "%s" by %s.',
        COALESCE(NEW.title, 'Untitled task'), status_label, actor_name);

    FOR recipient IN
        SELECT DISTINCT recipient_id
        FROM (
            SELECT NEW.assignee_id AS recipient_id
            UNION ALL
            SELECT unnest(COALESCE(NEW.assignee_ids, '{}'::UUID[]))
            UNION ALL
            SELECT unnest(COALESCE(NEW.watchers, '{}'::UUID[]))
        ) recipients
        WHERE recipient_id IS NOT NULL
          AND recipient_id IS DISTINCT FROM auth.uid()
    LOOP
        INSERT INTO public.notifications(
            user_id, message, event_type, task_id, actor_id, action_url, metadata
        )
        VALUES (
            recipient,
            task_message,
            'task_status_changed',
            NEW.id,
            auth.uid(),
            '/?view=tasks&task=' || NEW.id,
            jsonb_build_object(
                'task_title', NEW.title,
                'from_status', OLD.status,
                'to_status', NEW.status,
                'actor_name', actor_name
            )
        )
        RETURNING * INTO notification_row;

        BEGIN
            INSERT INTO public.task_email_outbox(
                notification_id, task_id, recipient_id, recipient_email,
                subject, message, action_url, always_send, context_type, details
            )
            SELECT
                notification_row.id,
                NEW.id,
                profile.id,
                auth_user.email,
                'Task status updated: ' || COALESCE(NEW.title, 'Untitled task'),
                task_message,
                '/?view=tasks&task=' || NEW.id,
                TRUE,
                'TASK',
                jsonb_strip_nulls(jsonb_build_object(
                    'Task title', NEW.title,
                    'Task creator', public.email_profile_name(NEW.created_by),
                    'Updated by', actor_name,
                    'Assigned to', public.email_profile_name(NEW.assignee_id),
                    'From status', OLD.status,
                    'To status', NEW.status,
                    'Event', 'task_status_changed'
                ))
            FROM public.profiles profile
            JOIN auth.users auth_user ON auth_user.id = profile.id
            WHERE profile.id = recipient
              AND NULLIF(BTRIM(auth_user.email), '') IS NOT NULL;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Unable to queue Task status email for recipient %: %', recipient, SQLERRM;
        END;
    END LOOP;

    RETURN NEW;
END;
$$;


--
-- Name: record_attendance_editor(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_attendance_editor() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    viewer_can_manage BOOLEAN := public.can_manage_attendance_records(auth.uid());
BEGIN
    IF viewer_can_manage THEN
        IF NEW.date IS DISTINCT FROM OLD.date
           OR NEW.clock_in_time IS DISTINCT FROM OLD.clock_in_time
           OR NEW.clock_in_location IS DISTINCT FROM OLD.clock_in_location THEN
            NEW.clock_in_edited_by := auth.uid();
            NEW.clock_in_edited_at := NOW();
        END IF;

        IF NEW.clock_out_time IS DISTINCT FROM OLD.clock_out_time
           OR NEW.clock_out_location IS DISTINCT FROM OLD.clock_out_location
           OR NEW.clock_out_type IS DISTINCT FROM OLD.clock_out_type
           OR NEW.overtime_hours IS DISTINCT FROM OLD.overtime_hours THEN
            NEW.clock_out_edited_by := auth.uid();
            NEW.clock_out_edited_at := NOW();
        END IF;
    ELSE
        -- Audit fields are database-managed and cannot be forged by employees.
        NEW.clock_in_edited_by := OLD.clock_in_edited_by;
        NEW.clock_in_edited_at := OLD.clock_in_edited_at;
        NEW.clock_out_edited_by := OLD.clock_out_edited_by;
        NEW.clock_out_edited_at := OLD.clock_out_edited_at;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: record_failed_login(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_failed_login(user_email text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO public.login_attempts (email, attempts, locked_until)
    VALUES (user_email, 1, NULL)
    ON CONFLICT (email) DO UPDATE 
    SET attempts = login_attempts.attempts + 1,
        locked_until = CASE 
            WHEN login_attempts.attempts + 1 >= 3 THEN NOW() + INTERVAL '24 hours'
            ELSE NULL
        END;
END;
$$;


--
-- Name: record_task_activity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_task_activity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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


--
-- Name: record_task_child_activity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_task_child_activity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE task_value uuid := COALESCE(NEW.task_id, OLD.task_id); action_value text;
BEGIN
  action_value := CASE WHEN TG_TABLE_NAME = 'task_comments' THEN CASE TG_OP WHEN 'INSERT' THEN 'COMMENT_ADDED' WHEN 'UPDATE' THEN 'COMMENT_EDITED' ELSE 'COMMENT_DELETED' END ELSE CASE TG_OP WHEN 'INSERT' THEN 'ATTACHMENT_ADDED' ELSE 'ATTACHMENT_ARCHIVED' END END;
  INSERT INTO public.task_activity(task_id, actor_id, action, metadata) VALUES (task_value, auth.uid(), action_value, jsonb_build_object('record_id', COALESCE(NEW.id, OLD.id)));
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;


--
-- Name: task_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    task_id uuid NOT NULL,
    user_id uuid,
    file_url text NOT NULL,
    file_name text NOT NULL,
    file_type text,
    file_size bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    visible_to_project_assignee boolean DEFAULT false NOT NULL,
    attachment_scope text DEFAULT 'TASK'::text NOT NULL,
    CONSTRAINT task_attachments_attachment_scope_check CHECK ((attachment_scope = ANY (ARRAY['TASK'::text, 'COMMENT'::text])))
);


--
-- Name: register_task_attachment(uuid, text, text, text, bigint, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_task_attachment(p_task_id uuid, p_file_url text, p_file_name text, p_file_type text DEFAULT NULL::text, p_file_size bigint DEFAULT NULL::bigint, p_attachment_scope text DEFAULT 'TASK'::text, p_visible boolean DEFAULT false) RETURNS public.task_attachments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: remove_task_attachment(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_task_attachment(p_attachment_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: request_workflow_after_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_workflow_after_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE req_type TEXT; financial BOOLEAN;
BEGIN
    IF TG_TABLE_NAME='leave_requests' THEN req_type:='Leave - '||NEW.leave_type;
    ELSIF TG_TABLE_NAME='document_requests' THEN req_type:=NEW.doc_type;
    ELSIF TG_TABLE_NAME='expenses' THEN req_type:='Expense / Item Purchase';
    ELSE
        req_type:=NEW.request_type;
        IF lower(COALESCE(NEW.request_type,'')) ~ '^loan( request)?$' AND NEW.loan_amount IS NOT NULL THEN
            req_type:=NEW.request_type||' - '||to_char(NEW.loan_amount,'FM999G999G999G990D00')||' SAR';
        END IF;
    END IF;
    financial:=lower(req_type) ~ '(loan|pay[ -]?slip|item purchase|purchase|expense)';
    PERFORM public.start_request_approval_workflow(TG_TABLE_NAME,NEW.id,NEW.employee_id,req_type,financial);
    RETURN NEW;
END; $_$;


--
-- Name: reset_login_lockout(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_login_lockout(user_email text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
    caller_role TEXT;
    caller_email TEXT;
BEGIN
    -- Get caller role
    SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
    
    -- Get caller email
    SELECT email INTO caller_email FROM auth.users WHERE id = auth.uid();

    -- Allow if Admin OR if the caller is the owner of the email
    IF caller_role = 'ADMIN' OR caller_email = user_email THEN
        UPDATE public.login_attempts
        SET attempts = 0, locked_until = NULL
        WHERE email = user_email;
    ELSE
        RAISE EXCEPTION 'Unauthorized';
    END IF;
END;
$$;


--
-- Name: reset_user_password(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reset_user_password(target_user_id uuid, new_password text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Only allow admins to execute
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'ADMIN') THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    UPDATE auth.users
    SET encrypted_password = crypt(new_password, gen_salt('bf'))
    WHERE id = target_user_id;
END;
$$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: save_user_directory_changes(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_user_directory_changes(p_changes jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    item JSONB;
    saved_count INTEGER := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles profile
        WHERE profile.id=auth.uid()
          AND upper(COALESCE(profile.role,'')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN')
    ) THEN
        RAISE EXCEPTION 'Only administrators can save the user directory' USING ERRCODE='42501';
    END IF;

    FOR item IN SELECT value FROM jsonb_array_elements(COALESCE(p_changes,'[]'::JSONB)) LOOP
        IF NULLIF(item->>'id','') IS NULL THEN RAISE EXCEPTION 'User id is required'; END IF;
        UPDATE public.profiles
        SET department_id=NULLIF(item->>'department_id','')::UUID,
            job_title=COALESCE(item->>'job_title',''),
            role=COALESCE(NULLIF(item->>'role',''),role),
            manager_id=NULLIF(item->>'manager_id','')::UUID
        WHERE id=(item->>'id')::UUID;
        IF FOUND THEN saved_count:=saved_count+1; END IF;
    END LOOP;
    RETURN jsonb_build_object('updated_count',saved_count);
END;
$$;


--
-- Name: set_employee_document_expiry_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_employee_document_expiry_status() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    NEW.status := CASE
        WHEN NEW.expiration_date IS NULL THEN 'Active'
        WHEN NEW.expiration_date - CURRENT_DATE <= 0 THEN 'Expired'
        WHEN NEW.expiration_date - CURRENT_DATE <= 30 THEN 'Expires Soon'
        ELSE 'Active'
    END;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.expiration_date IS DISTINCT FROM OLD.expiration_date THEN
            NEW.last_notification_status := NULL;
            NEW.last_notified_at := NULL;
            NEW.last_notification_error := NULL;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: set_hr_suite_beta_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_hr_suite_beta_audit() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_by := auth.uid();
    END IF;
    NEW.updated_by := auth.uid();
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;


--
-- Name: set_project_attachment_visibility(text, uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_project_attachment_visibility(p_attachment_type text, p_attachment_id uuid, p_visible boolean) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: set_project_todo_completed(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_project_todo_completed(p_todo_id uuid, p_completed boolean) RETURNS public.project_todos
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: set_task_employee_access_grant(uuid, uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_task_employee_access_grant(p_viewer_id uuid, p_subject_id uuid, p_enabled boolean DEFAULT true) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: start_crm_presentation_approval(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.start_crm_presentation_approval(p_deal_id uuid, p_request_type text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
    v_ceo uuid;
    v_gm uuid;
    v_mq04 uuid;
    v_mq05 uuid;
    v_marketing uuid;
BEGIN
    p_request_type := UPPER(BTRIM(COALESCE(p_request_type, '')));
    IF p_request_type NOT IN ('QUOTE', 'QUOTE_PROPOSAL') THEN
        RAISE EXCEPTION 'Choose Quote or Quote and proposal';
    END IF;

    SELECT * INTO v_deal
      FROM public.crm_deals
     WHERE id = p_deal_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deal not found';
    END IF;

    -- The CRM RLS policy already grants Sales, Marketing, CEO, GM and admin
    -- users access through can_access_crm(). The previous role-only check
    -- rejected regular Sales/Marketing users after their files were uploaded.
    IF NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You do not have access to start CRM approvals'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.crm_deal_attachments
         WHERE deal_id = p_deal_id AND category = 'QUOTATION'
    ) THEN
        RAISE EXCEPTION 'Upload a quote document first';
    END IF;
    IF p_request_type = 'QUOTE_PROPOSAL'
       AND NOT EXISTS (
           SELECT 1 FROM public.crm_deal_attachments
            WHERE deal_id = p_deal_id AND category = 'PROPOSAL'
       ) THEN
        RAISE EXCEPTION 'Upload at least one proposal image first';
    END IF;

    SELECT id INTO v_ceo
      FROM public.profiles
     WHERE is_active IS DISTINCT FROM false
       AND (
           UPPER(BTRIM(COALESCE(role, ''))) = 'CEO'
           OR UPPER(COALESCE(job_title, '')) ~ '(^|[^A-Z])(CEO|CHIEF EXECUTIVE)([^A-Z]|$)'
       )
     ORDER BY emp_index NULLS LAST
     LIMIT 1;

    SELECT id INTO v_gm
      FROM public.profiles
     WHERE is_active IS DISTINCT FROM false
       AND (
           UPPER(BTRIM(COALESCE(role, ''))) IN ('GM', 'GENERAL MANAGER')
           OR UPPER(COALESCE(job_title, '')) ~ '(^|[^A-Z])(GM|GENERAL MANAGER)([^A-Z]|$)'
       )
     ORDER BY emp_index NULLS LAST
     LIMIT 1;

    SELECT id INTO v_marketing
      FROM public.profiles
     WHERE is_active IS DISTINCT FROM false
       AND (
           UPPER(COALESCE(job_title, '')) ~ 'MARKETING.*MANAGER|MANAGER.*MARKETING'
           OR COALESCE(job_title, '') ~ 'مدير.*التسويق'
       )
     ORDER BY emp_index NULLS LAST
     LIMIT 1;

    SELECT id INTO v_mq04
      FROM public.profiles
     WHERE emp_index = 4 AND is_active IS DISTINCT FROM false
     LIMIT 1;

    SELECT id INTO v_mq05
      FROM public.profiles
     WHERE emp_index = 5 AND is_active IS DISTINCT FROM false
     LIMIT 1;

    IF v_ceo IS NULL OR v_gm IS NULL OR v_marketing IS NULL THEN
        RAISE EXCEPTION 'CEO, GM, and Marketing Manager accounts must be configured';
    END IF;
    IF p_request_type = 'QUOTE_PROPOSAL' AND (v_mq04 IS NULL OR v_mq05 IS NULL) THEN
        RAISE EXCEPTION 'Employee MQ-04 and MQ-05 accounts must be configured';
    END IF;

    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;
    INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
    VALUES
        (p_deal_id, 1, 'CEO', v_ceo),
        (p_deal_id, 2, 'GENERAL_MANAGER', v_gm);

    IF p_request_type = 'QUOTE_PROPOSAL' THEN
        INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
        VALUES
            (p_deal_id, 3, 'MQ_04', v_mq04),
            (p_deal_id, 4, 'MQ_05', v_mq05),
            (p_deal_id, 5, 'MARKETING_MANAGER', v_marketing);
    ELSE
        INSERT INTO public.crm_deal_approval_steps(deal_id, step_order, stage_key, approver_id)
        VALUES (p_deal_id, 3, 'MARKETING_MANAGER', v_marketing);
    END IF;

    UPDATE public.crm_deals
       SET stage = 'PITCH',
           approval_type = p_request_type,
           workflow_status = 'PENDING_APPROVAL',
           proposal_sent_at = now()
     WHERE id = p_deal_id;

    INSERT INTO public.notifications(user_id, message, event_type, actor_id, action_url, metadata)
    SELECT
        step.approver_id,
        CASE
            WHEN p_request_type = 'QUOTE' THEN 'Quote approval requested: '
            ELSE 'Quote and proposal approval requested: '
        END || COALESCE(v_deal.title, 'Untitled deal'),
        'crm_approval_requested',
        auth.uid(),
        '/?view=approvals',
        jsonb_build_object(
            'deal_id', p_deal_id,
            'step_id', step.id,
            'stage_key', step.stage_key,
            'request_type', p_request_type
        )
      FROM public.crm_deal_approval_steps step
     WHERE step.deal_id = p_deal_id;

    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, note, actor_id)
    VALUES (
        p_deal_id,
        'PRESENTATION_APPROVAL_STARTED',
        v_deal.stage,
        'PITCH',
        p_request_type,
        auth.uid()
    );
END;
$_$;


--
-- Name: start_deal_approval(uuid, uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.start_deal_approval(p_deal_id uuid, p_marketing_manager uuid, p_general_manager uuid, p_operations_manager uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_deal public.crm_deals%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_access_crm(auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to start CRM approval' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_deal FROM public.crm_deals WHERE id = p_deal_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'CRM deal not found' USING ERRCODE = 'P0002'; END IF;
    IF UPPER(COALESCE(v_deal.stage, '')) = 'LOST' THEN
        RAISE EXCEPTION 'Lost deals must be deliberately reopened before starting approval' USING ERRCODE = '42501';
    END IF;
    IF p_marketing_manager IS NULL OR p_general_manager IS NULL OR p_operations_manager IS NULL THEN
        RAISE EXCEPTION 'All approval reviewers are required' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM UNNEST(ARRAY[p_marketing_manager, p_general_manager, p_operations_manager]) reviewer_id
         WHERE NOT EXISTS (
             SELECT 1 FROM public.profiles reviewer
              WHERE reviewer.id = reviewer_id AND reviewer.is_active IS DISTINCT FROM false
         )
    ) THEN
        RAISE EXCEPTION 'All approval reviewers must be active employees' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.crm_deal_approval_steps WHERE deal_id = p_deal_id;
    INSERT INTO public.crm_deal_approval_steps (deal_id, step_order, stage_key, approver_id)
    VALUES
        (p_deal_id, 1, 'MARKETING_MANAGER', p_marketing_manager),
        (p_deal_id, 2, 'GENERAL_MANAGER', p_general_manager),
        (p_deal_id, 3, 'OPERATIONS_MANAGER', p_operations_manager);
    UPDATE public.crm_deals
       SET stage = 'PITCH', workflow_status = 'PENDING_APPROVAL',
           proposal_sent_at = COALESCE(proposal_sent_at, now())
     WHERE id = p_deal_id;
    INSERT INTO public.crm_deal_activity(deal_id, action, from_status, to_status, actor_id)
    VALUES (p_deal_id, 'APPROVAL_STARTED', v_deal.stage, 'PITCH', auth.uid());
END;
$$;


--
-- Name: start_request_approval_workflow(text, uuid, uuid, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.start_request_approval_workflow(p_source_table text, p_source_id uuid, p_employee_id uuid, p_request_type text, p_is_financial boolean DEFAULT false) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_workflow_id UUID; employee public.profiles%ROWTYPE; department_manager UUID; accountant_manager UUID; general_manager UUID; fallback_manager UUID;
DECLARE approvers UUID[] := '{}'; inserted_approvers UUID[] := '{}'; stages TEXT[] := '{}'; candidate UUID; stage TEXT; position INTEGER := 0; idx INTEGER;
BEGIN
    SELECT w.id INTO v_workflow_id FROM public.request_approval_workflows w WHERE w.source_table=p_source_table AND w.source_id=p_source_id;
    IF v_workflow_id IS NOT NULL THEN RETURN v_workflow_id; END IF;
    SELECT * INTO employee FROM public.profiles WHERE id=p_employee_id;
    SELECT head_id INTO department_manager FROM public.departments WHERE id=employee.department_id;

    SELECT id INTO accountant_manager
    FROM public.profiles
    WHERE is_active IS DISTINCT FROM FALSE
      AND (upper(trim(COALESCE(job_title,''))) IN ('FINANCE MANAGER','ACCOUNTING MANAGER','ACCOUNTANT MANAGER','SENIOR ACCOUNTANT','ACCOUNTANT')
           OR upper(trim(COALESCE(role,'')))='ACCOUNTANT_MANAGER')
    ORDER BY CASE WHEN upper(trim(COALESCE(job_title,''))) IN ('FINANCE MANAGER','ACCOUNTING MANAGER','ACCOUNTANT MANAGER') THEN 0 ELSE 1 END, created_at
    LIMIT 1;

    IF accountant_manager IS NULL THEN
        SELECT head_id INTO accountant_manager
        FROM public.departments
        WHERE upper(trim(name)) LIKE '%FINANCE%' OR upper(trim(name)) LIKE '%ACCOUNTING%'
        ORDER BY CASE WHEN head_id IS NOT NULL THEN 0 ELSE 1 END
        LIMIT 1;
    END IF;

    SELECT id INTO general_manager FROM public.profiles WHERE is_active IS DISTINCT FROM FALSE AND (upper(trim(COALESCE(job_title,''))) LIKE '%GENERAL MANAGER%' OR upper(trim(COALESCE(role,'')))='GENERAL_MANAGER') ORDER BY created_at LIMIT 1;
    SELECT id INTO fallback_manager FROM public.profiles WHERE upper(trim(COALESCE(role,''))) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN') ORDER BY created_at LIMIT 1;

    approvers := ARRAY[employee.manager_id,department_manager];
    stages := ARRAY['SUPERVISOR_MANAGER','DEPARTMENT_MANAGER'];
    IF p_is_financial THEN
        accountant_manager := COALESCE(accountant_manager, fallback_manager);
        general_manager := COALESCE(general_manager, fallback_manager);
        approvers := approvers||ARRAY[accountant_manager,general_manager];
        stages := stages||ARRAY['ACCOUNTANT_MANAGER','GENERAL_MANAGER'];
    END IF;

    INSERT INTO public.request_approval_workflows(source_table,source_id,employee_id,request_type,is_financial)
    VALUES(p_source_table,p_source_id,p_employee_id,p_request_type,p_is_financial)
    RETURNING id INTO v_workflow_id;

    FOR idx IN 1..array_length(approvers,1) LOOP
        candidate:=approvers[idx]; stage:=stages[idx];
        IF candidate IS NOT NULL AND candidate<>p_employee_id AND NOT candidate=ANY(inserted_approvers) THEN
            position:=position+1;
            INSERT INTO public.request_approval_steps(workflow_id,step_order,stage_key,approver_id) VALUES(v_workflow_id,position,stage,candidate);
            inserted_approvers:=array_append(inserted_approvers,candidate);
        END IF;
    END LOOP;

    IF position=0 AND fallback_manager IS NOT NULL THEN
        position:=1;
        INSERT INTO public.request_approval_steps(workflow_id,step_order,stage_key,approver_id) VALUES(v_workflow_id,1,'ADMIN_FALLBACK',fallback_manager);
    END IF;
    IF position=0 THEN RAISE EXCEPTION 'No approver is configured for this employee request'; END IF;
    SELECT approver_id INTO candidate FROM public.request_approval_steps WHERE workflow_id=v_workflow_id AND step_order=1;
    PERFORM public.queue_request_notification(candidate,'Approval required: '||p_request_type,'request_approval_required',v_workflow_id);
    PERFORM public.queue_request_notification(p_employee_id,'Your '||p_request_type||' request was submitted and is awaiting approval.','request_status_changed',v_workflow_id);
    RETURN v_workflow_id;
END;
$$;


--
-- Name: sync_contract_identity_to_profile(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_contract_identity_to_profile() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    UPDATE public.profiles
    SET
        iqama_number = COALESCE(NULLIF(BTRIM(NEW.identity_number), ''), iqama_number),
        phone_number = COALESCE(NULLIF(BTRIM(NEW.employee_phone), ''), phone_number)
    WHERE id = NEW.employee_id;
    RETURN NEW;
END;
$$;


--
-- Name: sync_crm_design_task_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_crm_design_task_status() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_status text;
BEGIN
    IF NEW.crm_workflow_kind IS DISTINCT FROM 'QUOTE_PROPOSAL_DESIGN' OR NEW.crm_deal_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_status := CASE
        WHEN LOWER(BTRIM(COALESCE(NEW.status, ''))) IN ('completed', 'approved', 'pending approval') THEN 'COMPLETED'
        WHEN LOWER(BTRIM(COALESCE(NEW.status, ''))) = 'late' THEN 'LATE'
        WHEN NEW.due_date IS NOT NULL AND NEW.due_date < CURRENT_DATE THEN 'LATE'
        ELSE 'IN_PROGRESS'
    END;

    UPDATE public.crm_deals
       SET design_task_status = v_status,
           design_task_due_date = NEW.due_date
     WHERE id = NEW.crm_deal_id;
    RETURN NEW;
END;
$$;


--
-- Name: sync_department_head_from_manager_title(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_department_head_from_manager_title() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE department_name TEXT;
BEGIN
    IF NEW.department_id IS NULL OR NEW.job_title IS NULL THEN RETURN NEW; END IF;
    SELECT name INTO department_name FROM public.departments WHERE id=NEW.department_id;
    IF lower(BTRIM(NEW.job_title))=lower(BTRIM(department_name||' Manager')) THEN
        UPDATE public.departments SET head_id=NEW.id WHERE id=NEW.department_id;
    END IF;
    RETURN NEW;
END; $$;


--
-- Name: sync_employee_login_accounts(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_employee_login_accounts(temporary_password text, apply_changes boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions', 'pg_temp'
    AS $$
DECLARE
    caller_is_admin BOOLEAN;
    admin_user_id UUID;
    employee_record RECORD;
    account_count INTEGER := 0;
    deleted_count INTEGER := 0;
    email_accounts JSONB := '[]'::JSONB;
    missing_email_employees JSONB := '[]'::JSONB;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = auth.uid()
          AND UPPER(COALESCE(role, '')) IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
    ) INTO caller_is_admin;

    IF NOT caller_is_admin THEN
        RAISE EXCEPTION 'Only a system administrator can synchronize employee accounts';
    END IF;

    IF apply_changes AND (
        temporary_password IS NULL
        OR LENGTH(temporary_password) < 8
        OR temporary_password !~ '[A-Z]'
        OR temporary_password !~ '[a-z]'
        OR temporary_password !~ '[0-9]'
    ) THEN
        RAISE EXCEPTION 'The temporary password does not meet the minimum security requirements';
    END IF;

    admin_user_id := auth.uid();

    FOR employee_record IN
        SELECT
            profile.id,
            profile.full_name,
            profile.emp_index,
            profile.role,
            NULLIF(BTRIM(auth_user.email), '') AS email
        FROM public.profiles profile
        LEFT JOIN auth.users auth_user ON auth_user.id = profile.id
        WHERE UPPER(COALESCE(profile.role, 'EMPLOYEE')) NOT IN ('ADMIN', 'ROLE_SYSTEM_ADMIN', 'SYSTEM_ADMIN')
        ORDER BY profile.emp_index NULLS LAST, profile.full_name
    LOOP
        IF employee_record.email IS NULL THEN
            missing_email_employees := missing_email_employees || jsonb_build_array(jsonb_build_object(
                'id', employee_record.id,
                'employee_number', employee_record.emp_index,
                'name', employee_record.full_name,
                'role', employee_record.role
            ));

            IF apply_changes THEN
                -- The user requested complete removal. Delete contracts first
                -- so the normal employee deletion routine cannot archive and
                -- retain personal details for an employee without an email.
                DELETE FROM public.contracts WHERE employee_id = employee_record.id;

                -- Reuse the established dependency-aware deletion routine.
                -- auth.uid() remains the signed-in administrator.
                PERFORM public.archive_and_delete_employee(employee_record.id);
                deleted_count := deleted_count + 1;
            END IF;
        ELSE
            email_accounts := email_accounts || jsonb_build_array(jsonb_build_object(
                'id', employee_record.id,
                'employee_number', employee_record.emp_index,
                'name', employee_record.full_name,
                'email', LOWER(employee_record.email),
                'role', employee_record.role
            ));

            IF apply_changes THEN
                UPDATE auth.users
                SET
                    email = LOWER(employee_record.email),
                    encrypted_password = extensions.crypt(temporary_password, extensions.gen_salt('bf')),
                    email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
                    confirmation_token = '',
                    recovery_token = '',
                    email_change = '',
                    email_change_token_new = '',
                    raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::JSONB)
                        || '{"provider":"email","providers":["email"]}'::JSONB,
                    raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::JSONB)
                        || jsonb_build_object('temporary_password', TRUE),
                    updated_at = NOW()
                WHERE id = employee_record.id;

                UPDATE auth.identities
                SET
                    provider_id = LOWER(employee_record.email),
                    identity_data = COALESCE(identity_data, '{}'::JSONB)
                        || jsonb_build_object('sub', employee_record.id::TEXT, 'email', LOWER(employee_record.email)),
                    updated_at = NOW()
                WHERE user_id = employee_record.id AND provider = 'email';

                IF NOT FOUND THEN
                    INSERT INTO auth.identities (
                        id, provider_id, user_id, identity_data, provider,
                        last_sign_in_at, created_at, updated_at
                    ) VALUES (
                        gen_random_uuid(), LOWER(employee_record.email), employee_record.id,
                        jsonb_build_object('sub', employee_record.id::TEXT, 'email', LOWER(employee_record.email)),
                        'email', NOW(), NOW(), NOW()
                    );
                END IF;

                account_count := account_count + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'applied', apply_changes,
        'accounts_to_create_or_reset', jsonb_array_length(email_accounts),
        'employees_to_delete', jsonb_array_length(missing_email_employees),
        'accounts_updated', account_count,
        'employees_deleted', deleted_count,
        'accounts', email_accounts,
        'missing_email_employees', missing_email_employees,
        'executed_by', admin_user_id
    );
END;
$$;


--
-- Name: FUNCTION sync_employee_login_accounts(temporary_password text, apply_changes boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.sync_employee_login_accounts(temporary_password text, apply_changes boolean) IS 'Previews or applies employee login synchronization. Non-admin employees with email receive the supplied temporary password; non-admin employees without email are fully removed.';


--
-- Name: task_belongs_to_employee(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.task_belongs_to_employee(p_task_id uuid, p_employee_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: touch_project_from_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.touch_project_from_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    UPDATE public.projects
    SET last_update = NEW.summary, last_update_at = NEW.created_at, updated_at = NOW()
    WHERE id = NEW.project_id;
    RETURN NEW;
END;
$$;


--
-- Name: update_project_secure(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_project_secure(p_project_id uuid, p_changes jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_user UUID := auth.uid();
    v_current public.projects%ROWTYPE;
    v_next public.projects%ROWTYPE;
    v_patch JSONB;
BEGIN
    IF v_user IS NULL OR NOT public.can_access_project(p_project_id, v_user) THEN RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501'; END IF;
    SELECT * INTO v_current FROM public.projects WHERE id = p_project_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project not found' USING ERRCODE = 'P0002'; END IF;
    IF NOT (public.is_project_portfolio_admin(v_user) OR v_current.created_by = v_user OR v_current.project_manager_id = v_user) THEN
        RAISE EXCEPTION 'Only the project owner or manager can update project details' USING ERRCODE = '42501';
    END IF;
    IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'object' THEN RAISE EXCEPTION 'Project changes must be an object' USING ERRCODE = '22023'; END IF;
    IF (p_changes ? 'budget_amount' OR p_changes ? 'actual_cost') AND NOT public.can_view_business_financials(v_user) THEN
        RAISE EXCEPTION 'Financial project fields are restricted' USING ERRCODE = '42501';
    END IF;
    -- Strip relationships, ownership, status transitions, audit columns, and unknown fields.
    v_patch := p_changes - ARRAY['id','created_at','updated_at','created_by','project_manager_id','assigned_people','deal_id','client_id','project_amount','paid_amount','project_status','source','order_employee_id','client_snapshot','equipment','lifecycle_status','last_update','last_update_at'];
    v_next := jsonb_populate_record(v_current, v_patch);
    UPDATE public.projects SET
        project_name=v_next.project_name, project_type=v_next.project_type, description=v_next.description,
        project_category=v_next.project_category, project_tags=v_next.project_tags, health_status=v_next.health_status,
        priority=v_next.priority, progress_percent=v_next.progress_percent, budget_amount=v_next.budget_amount,
        actual_cost=v_next.actual_cost, client_name=v_next.client_name, milestones=v_next.milestones, risks=v_next.risks,
        start_date=v_next.start_date, end_date=v_next.end_date, event_date=v_next.event_date,
        uninstallation_date=v_next.uninstallation_date, event_location=v_next.event_location,
        event_location_text=v_next.event_location_text, installation_type=v_next.installation_type,
        event_start_time=v_next.event_start_time, installation_time=v_next.installation_time,
        uninstallation_time=v_next.uninstallation_time, updated_at=NOW()
    WHERE id=p_project_id RETURNING * INTO v_next;
    RETURN to_jsonb(v_next) || jsonb_build_object(
        'project_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.project_amount) ELSE 'null'::JSONB END,
        'paid_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.paid_amount) ELSE 'null'::JSONB END,
        'budget_amount', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.budget_amount) ELSE 'null'::JSONB END,
        'actual_cost', CASE WHEN public.can_view_business_financials(v_user) THEN to_jsonb(v_next.actual_cost) ELSE 'null'::JSONB END
    );
END;
$$;


--
-- Name: update_task_comment(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_task_comment(p_comment_id uuid, p_content text, p_attachments jsonb DEFAULT NULL::jsonb) RETURNS public.task_comments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
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
$_$;


--
-- Name: update_task_secure(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_task_secure(p_task_id uuid, p_patch jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_task public.tasks%ROWTYPE;
    v_next public.tasks%ROWTYPE;
    v_safe jsonb := '{}'::jsonb;
    v_result jsonb;
    v_key text;
BEGIN
    IF auth.uid() IS NULL OR NOT public.can_manage_task(p_task_id, auth.uid()) THEN
        RAISE EXCEPTION 'You are not authorized to update this task' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Task not found' USING ERRCODE = 'P0002'; END IF;
    FOR v_key IN SELECT unnest(ARRAY[
        'title','description','due_date','priority','category','title_i18n',
        'description_i18n','start_date','end_date','estimated_time','visibility',
        'project_id','tags','visible_to','content_type','source_link','upload_link',
        'department','sub_type','watchers','parent_task_id','marketing_department',
        'content_links','submission_links','delivery_status','task_list_id',
        'repeat_type','repeat_interval','notify_via_email','crm_deal_id','crm_workflow_kind'
    ]) LOOP
        IF p_patch ? v_key THEN v_safe := v_safe || jsonb_build_object(v_key, p_patch->v_key); END IF;
    END LOOP;
    IF v_safe ? 'title' AND NULLIF(BTRIM(v_safe->>'title'), '') IS NULL THEN
        RAISE EXCEPTION 'Task title is required' USING ERRCODE = '22023';
    END IF;
    IF v_safe ? 'project_id' AND NULLIF(v_safe->>'project_id', '') IS NOT NULL
       AND NOT public.can_access_project((v_safe->>'project_id')::uuid, auth.uid()) THEN
        RAISE EXCEPTION 'Project access denied' USING ERRCODE = '42501';
    END IF;
    IF v_safe ? 'task_list_id' AND NULLIF(v_safe->>'task_list_id', '') IS NOT NULL
       AND NOT public.can_add_task_to_list((v_safe->>'task_list_id')::uuid, auth.uid()) THEN
        RAISE EXCEPTION 'Task-list access denied' USING ERRCODE = '42501';
    END IF;
    v_next := jsonb_populate_record(v_task, v_safe);
    UPDATE public.tasks SET
        title = v_next.title, description = v_next.description, due_date = v_next.due_date,
        priority = v_next.priority, category = v_next.category, title_i18n = v_next.title_i18n,
        description_i18n = v_next.description_i18n, start_date = v_next.start_date,
        end_date = v_next.end_date, estimated_time = v_next.estimated_time,
        visibility = v_next.visibility, project_id = v_next.project_id, tags = v_next.tags,
        visible_to = v_next.visible_to, content_type = v_next.content_type,
        source_link = v_next.source_link, upload_link = v_next.upload_link,
        department = v_next.department, sub_type = v_next.sub_type, watchers = v_next.watchers,
        parent_task_id = v_next.parent_task_id, marketing_department = v_next.marketing_department,
        content_links = v_next.content_links, submission_links = v_next.submission_links,
        delivery_status = v_next.delivery_status, task_list_id = v_next.task_list_id,
        repeat_type = v_next.repeat_type, repeat_interval = v_next.repeat_interval,
        notify_via_email = v_next.notify_via_email, crm_deal_id = v_next.crm_deal_id,
        crm_workflow_kind = v_next.crm_workflow_kind
     WHERE id = p_task_id
     RETURNING to_jsonb(tasks) INTO v_result;
    RETURN v_result;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   NEW.updated_at = NOW();
   RETURN NEW;
END;
$$;


--
-- Name: validate_leave_request_days(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_leave_request_days() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF NEW.request_type='Leave Request' AND (NEW.number_of_days IS NULL OR NEW.number_of_days<=0) THEN
        RAISE EXCEPTION 'Number of leave days must be a positive whole number';
    END IF;
    IF NEW.request_type<>'Leave Request' THEN NEW.number_of_days:=NULL; END IF;
    RETURN NEW;
END; $$;


--
-- Name: validate_loan_request_amount(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_loan_request_amount() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $_$
BEGIN
    IF lower(COALESCE(NEW.request_type,'')) ~ '^loan( request)?$'
       AND (NEW.loan_amount IS NULL OR NEW.loan_amount<=0) THEN
        RAISE EXCEPTION 'Loan amount must be greater than zero SAR';
    END IF;
    IF NOT (lower(COALESCE(NEW.request_type,'')) ~ '^loan( request)?$') THEN NEW.loan_amount:=NULL; END IF;
    RETURN NEW;
END; $_$;


--
-- Name: validate_profile_job_title(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_profile_job_title() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF TG_OP='UPDATE' AND NEW.job_title IS NOT DISTINCT FROM OLD.job_title AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id THEN RETURN NEW; END IF;
    IF NULLIF(BTRIM(COALESCE(NEW.job_title,'')),'') IS NULL THEN RETURN NEW; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.job_titles WHERE is_active=TRUE AND lower(name)=lower(BTRIM(NEW.job_title))) THEN
        RAISE EXCEPTION 'Please select an active job title from the company catalog';
    END IF;
    IF NEW.department_id IS NOT NULL AND NOT EXISTS(
        SELECT 1 FROM public.job_titles WHERE is_active=TRUE AND department_id=NEW.department_id AND lower(name)=lower(BTRIM(NEW.job_title))
    ) THEN RAISE EXCEPTION 'The selected job title does not belong to the selected department'; END IF;
    RETURN NEW;
END; $$;


--
-- Name: validate_shared_attachment_metadata(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_shared_attachment_metadata() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
    v_type text := LOWER(BTRIM(COALESCE(NEW.file_type, '')));
    v_name text := LOWER(BTRIM(COALESCE(NEW.file_name, '')));
    v_url text := BTRIM(COALESCE(NEW.file_url, ''));
BEGIN
    IF NEW.file_size IS NOT NULL AND (NEW.file_size < 0 OR NEW.file_size > 26214400) THEN
        RAISE EXCEPTION 'Attachment exceeds the 25 MB limit' USING ERRCODE = '22023';
    END IF;
    IF v_type <> '' AND v_type NOT IN (
        'application/pdf','image/jpeg','image/png','image/webp','text/plain',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ) THEN
        RAISE EXCEPTION 'This file type is not allowed' USING ERRCODE = '22023';
    END IF;
    IF v_name ~ '\.(exe|com|bat|cmd|scr|js|vbs|ps1|sh|dll)(\.|$)' THEN
        RAISE EXCEPTION 'Executable attachments are not allowed' USING ERRCODE = '22023';
    END IF;
    IF TG_TABLE_NAME = 'task_attachments' AND v_url !~ '^storage://task-attachments/[A-Za-z0-9._/-]+$' THEN
        RAISE EXCEPTION 'Invalid task attachment storage reference' USING ERRCODE = '22023';
    ELSIF TG_TABLE_NAME = 'crm_deal_attachments' AND v_url !~ '^storage://crm-deal-files/[A-Za-z0-9._/-]+$' THEN
        RAISE EXCEPTION 'Invalid deal attachment storage reference' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$_$;


--
-- Name: validate_short_leave_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_short_leave_request() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF NEW.leave_type='Short Leave' THEN
        IF NEW.short_leave_reason NOT IN (
            'I am running late to the office.',
            'I will be out for a meeting.',
            'I need to attend an urgent family matter.',
            'I have an important outing to run.'
        ) THEN RAISE EXCEPTION 'Select a valid short leave reason'; END IF;
        IF NEW.short_leave_duration_minutes NOT IN (15,60,120,180,1440) THEN
            RAISE EXCEPTION 'Short leave duration must be 15, 60, 120, 180 or 1440 minutes';
        END IF;
        NEW.start_date:=COALESCE(NEW.start_date,CURRENT_DATE);
        NEW.end_date:=NEW.start_date;
        NEW.reason:=NEW.short_leave_reason;
    ELSE
        NEW.short_leave_reason:=NULL;
        NEW.short_leave_duration_minutes:=NULL;
    END IF;
    RETURN NEW;
END; $$;


--
-- Name: validate_task_department_supervisor(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_task_department_supervisor() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE expected_supervisor_id uuid; caller_role text;
BEGIN
  IF NEW.task_list_id IS NOT NULL THEN RETURN NEW; END IF;
  SELECT role INTO caller_role FROM public.profiles WHERE id = auth.uid();
  IF UPPER(COALESCE(caller_role, '')) IN ('ADMIN','ROLE_SYSTEM_ADMIN','SYSTEM_ADMIN') THEN RETURN NEW; END IF;
  SELECT department.head_id INTO expected_supervisor_id
  FROM public.profiles creator LEFT JOIN public.departments department ON department.id = creator.department_id
  WHERE creator.id = NEW.created_by;
  IF NEW.supervisor_id IS DISTINCT FROM expected_supervisor_id THEN
    RAISE EXCEPTION 'Selected supervisor must be the task creator''s department manager' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: validate_task_list_department_access(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_task_list_department_access() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: validate_task_list_department_visibility(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_task_list_department_visibility() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: validate_task_list_sharing(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_task_list_sharing() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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


--
-- Name: absences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.absences (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    date_of_absence date NOT NULL,
    is_excused boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: admin_password_reset_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_password_reset_audit (
    id bigint NOT NULL,
    actor_user_id uuid NOT NULL,
    target_user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: admin_password_reset_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.admin_password_reset_audit ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.admin_password_reset_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: announcements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.announcements (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    icon character varying(50) DEFAULT 'megaphone'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    admin_id uuid
);


--
-- Name: attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    date date DEFAULT CURRENT_DATE NOT NULL,
    clock_in_time timestamp with time zone DEFAULT now() NOT NULL,
    clock_out_time timestamp with time zone,
    clock_in_location text,
    clock_out_location text,
    clock_out_type character varying(50),
    overtime_hours numeric(5,2) DEFAULT 0.00,
    created_at timestamp with time zone DEFAULT now(),
    order_location_latitude numeric(10,7),
    order_location_longitude numeric(10,7),
    order_location_accuracy numeric(10,2),
    order_location_shared_at timestamp with time zone,
    order_location_photo_path text,
    clock_in_edited_by uuid,
    clock_in_edited_at timestamp with time zone,
    clock_out_edited_by uuid,
    clock_out_edited_at timestamp with time zone,
    CONSTRAINT attendance_clock_out_type_check CHECK (((clock_out_type)::text = ANY ((ARRAY['OFFICE'::character varying, 'ORDER'::character varying])::text[])))
);


--
-- Name: COLUMN attendance.clock_in_edited_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.clock_in_edited_by IS 'Administrator or executive who last corrected the clock-in punch.';


--
-- Name: COLUMN attendance.clock_out_edited_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.clock_out_edited_by IS 'Administrator or executive who last corrected the clock-out punch.';


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    entity_type character varying(100) NOT NULL,
    entity_id uuid NOT NULL,
    action character varying(100) NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: candidates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.candidates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    job_id uuid,
    first_name character varying(100),
    last_name character varying(100),
    email character varying(255),
    phone character varying(50),
    resume_url text,
    status character varying(50) DEFAULT 'APPLIED'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT candidates_status_check CHECK (((status)::text = ANY ((ARRAY['APPLIED'::character varying, 'SCREENING'::character varying, 'INTERVIEW'::character varying, 'OFFERED'::character varying, 'HIRED'::character varying, 'REJECTED'::character varying])::text[])))
);


--
-- Name: commission_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commission_tiers (
    id integer NOT NULL,
    min_target_percentage numeric(5,2) NOT NULL,
    max_target_percentage numeric(5,2),
    commission_percentage numeric(5,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: commission_tiers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.commission_tiers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: commission_tiers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.commission_tiers_id_seq OWNED BY public.commission_tiers.id;


--
-- Name: community_chat; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.community_chat (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    message text NOT NULL,
    is_birthday_alert boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: contract_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contract_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    file_name text NOT NULL,
    file_url text NOT NULL,
    document_type text DEFAULT 'contract_attachment'::text NOT NULL,
    uploaded_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: contract_print_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_print_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contract_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    manager_id uuid,
    status text DEFAULT 'PENDING'::text NOT NULL,
    manager_note text,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    decided_at timestamp with time zone,
    CONSTRAINT contract_print_requests_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'APPROVED'::text, 'REJECTED'::text])))
);


--
-- Name: contract_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_settings (
    id integer NOT NULL,
    max_probation_days integer DEFAULT 180,
    default_notice_period_days integer DEFAULT 60,
    default_currency character varying(10) DEFAULT 'SAR'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: contract_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_settings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_settings_id_seq OWNED BY public.contract_settings.id;


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid,
    contract_type character varying(50) DEFAULT 'Full-time'::character varying,
    start_date date,
    end_date date,
    salary numeric(10,2),
    status character varying(20) DEFAULT 'Active'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    housing_allowance numeric(10,2) DEFAULT 0.00,
    transportation_allowance numeric(10,2) DEFAULT 0.00,
    other_allowances numeric(10,2) DEFAULT 0.00,
    working_hours character varying(50) DEFAULT '8 hours/day'::character varying,
    probation_period_days integer DEFAULT 90,
    notice_period_days integer DEFAULT 30,
    annual_leave_days integer DEFAULT 30,
    internal_contract_number character varying(100),
    contract_language character varying(50) DEFAULT 'Arabic/English'::character varying,
    qiwa_reference_number character varying(100),
    previous_contract_id uuid,
    employer_name_ar character varying(255),
    employer_name_en character varying(255),
    commercial_registration character varying(50),
    unified_establishment_number character varying(50),
    employer_address text,
    employer_city character varying(100),
    employer_region character varying(100),
    authorized_rep_name character varying(255),
    authorized_rep_title character varying(255),
    employee_number character varying(100),
    employee_name_ar character varying(255),
    employee_name_en character varying(255),
    nationality character varying(100),
    is_saudi boolean DEFAULT true,
    identity_document_type character varying(100),
    identity_number character varying(100),
    identity_expiry_date date,
    date_of_birth date,
    employee_address text,
    employee_city character varying(100),
    employee_region character varying(100),
    employee_mobile character varying(50),
    employee_email character varying(255),
    profession character varying(255),
    job_title_ar character varying(255),
    job_title_en character varying(255),
    department character varying(255),
    reporting_manager character varying(255),
    work_type character varying(100),
    primary_workplace character varying(255),
    work_city character varying(100),
    work_region character varying(100),
    work_arrangement character varying(100),
    employment_commencement_date date,
    contract_duration_desc character varying(255),
    renewal_option character varying(255),
    project_description text,
    probation_enabled boolean DEFAULT false,
    probation_end_date date,
    probation_terms text,
    basic_monthly_wage numeric(10,2) DEFAULT 0.00,
    commission_details text,
    bonus_details text,
    in_kind_benefits text,
    wage_payment_frequency character varying(100) DEFAULT 'Monthly'::character varying,
    wage_payment_schedule character varying(255),
    payment_method character varying(100) DEFAULT 'Bank Transfer'::character varying,
    bank_name character varying(255),
    iban character varying(100),
    overtime_treatment character varying(255),
    financial_deductions text,
    additional_financial_obligations text,
    working_days_per_week integer DEFAULT 5,
    daily_working_hours integer DEFAULT 8,
    weekly_working_hours integer DEFAULT 40,
    shift_type character varying(100),
    daily_rest_arrangements text,
    weekly_rest_day character varying(100) DEFAULT 'Friday, Saturday'::character varying,
    ramadan_schedule_applicability boolean DEFAULT true,
    official_holidays text,
    sick_leave_reference text,
    other_leaves_reference text,
    medical_insurance_details text,
    social_insurance_applicability boolean DEFAULT true,
    housing_benefit text,
    transportation_benefit text,
    employee_duties text,
    employer_obligations text,
    confidentiality_clause text,
    intellectual_property_clause text,
    data_protection_clause text,
    health_safety_clause text,
    transfer_relocation_clause text,
    training_obligations text,
    non_compete_clause text,
    termination_clause text,
    end_of_service_benefits_clause text,
    dispute_resolution text,
    governing_law character varying(255) DEFAULT 'Saudi Labor Law'::character varying,
    additional_clauses text,
    department_id uuid,
    confidentiality_policy_url text,
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    former_employee_name text,
    former_employee_email text,
    former_employee_number text,
    employee_phone text,
    edited_by text,
    CONSTRAINT contracts_status_check CHECK (((status)::text = ANY ((ARRAY['Draft'::character varying, 'Pending Review'::character varying, 'Pending Employee Approval'::character varying, 'Active'::character varying, 'Rejected'::character varying, 'Expired'::character varying, 'Terminated'::character varying, 'Resigned'::character varying, 'Cancelled'::character varying])::text[])))
);


--
-- Name: crm_clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_clients (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    company text,
    status text DEFAULT 'ACTIVE'::text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    assigned_to uuid
);


--
-- Name: crm_deal_activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_deal_activity (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    deal_id uuid NOT NULL,
    action text NOT NULL,
    from_status text,
    to_status text,
    note text,
    actor_id uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: crm_deal_approval_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_deal_approval_steps (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    deal_id uuid NOT NULL,
    step_order integer NOT NULL,
    stage_key text NOT NULL,
    approver_id uuid,
    status text DEFAULT 'PENDING'::text NOT NULL,
    decision_note text,
    decided_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT crm_deal_approval_steps_stage_key_check CHECK ((stage_key = ANY (ARRAY['CEO'::text, 'GENERAL_MANAGER'::text, 'MQ_04'::text, 'MQ_05'::text, 'MARKETING_MANAGER'::text, 'OPERATIONS_MANAGER'::text]))),
    CONSTRAINT crm_deal_approval_steps_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'APPROVED'::text, 'REJECTED'::text]))),
    CONSTRAINT crm_deal_approval_steps_step_order_check CHECK (((step_order >= 1) AND (step_order <= 5)))
);


--
-- Name: crm_deal_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_deal_attachments (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    deal_id uuid NOT NULL,
    category text DEFAULT 'OTHER'::text NOT NULL,
    file_name text NOT NULL,
    file_url text NOT NULL,
    description text,
    uploaded_by uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    visible_to_project_assignee boolean DEFAULT false NOT NULL,
    file_type text,
    file_size bigint,
    CONSTRAINT crm_deal_attachments_category_check CHECK ((category = ANY (ARRAY['QUOTATION'::text, 'CLIENT_IDENTITY'::text, 'TECHNICAL_PRESENTATION'::text, 'PROPOSAL'::text, 'PHOTO'::text, 'OTHER'::text])))
);


--
-- Name: crm_deals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_deals (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    client_id uuid,
    title text NOT NULL,
    amount numeric(12,2) DEFAULT 0.00,
    stage text DEFAULT 'LEAD'::text NOT NULL,
    closing_date date,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    assigned_to uuid,
    lost_reason text,
    event_type text,
    first_contact_date date,
    contact_method text,
    lead_source text,
    workflow_status text DEFAULT 'NOT_STARTED'::text NOT NULL,
    technical_description text,
    proposal_sent_at timestamp with time zone,
    created_by uuid,
    approval_type text,
    design_task_id uuid,
    design_task_status text,
    design_task_due_date date,
    CONSTRAINT crm_deals_approval_type_check CHECK (((approval_type IS NULL) OR (approval_type = ANY (ARRAY['QUOTE'::text, 'QUOTE_PROPOSAL'::text])))),
    CONSTRAINT crm_deals_design_task_status_check CHECK (((design_task_status IS NULL) OR (design_task_status = ANY (ARRAY['IN_PROGRESS'::text, 'LATE'::text, 'COMPLETED'::text])))),
    CONSTRAINT crm_deals_stage_check CHECK ((stage = ANY (ARRAY['LEAD'::text, 'QUALIFICATION'::text, 'PITCH'::text, 'PROPOSAL'::text, 'NEGOTIATION'::text, 'WON'::text, 'LOST'::text]))),
    CONSTRAINT crm_deals_workflow_status_check CHECK ((workflow_status = ANY (ARRAY['NOT_STARTED'::text, 'PENDING_APPROVAL'::text, 'APPROVED'::text, 'REJECTED'::text, 'DESIGN_IN_PROGRESS'::text, 'DESIGN_PENDING_APPROVAL'::text, 'DESIGN_REJECTED'::text])))
);


--
-- Name: crm_design_task_approval_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_design_task_approval_steps (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    task_id uuid NOT NULL,
    deal_id uuid NOT NULL,
    step_order integer NOT NULL,
    stage_key text NOT NULL,
    approver_id uuid NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    decision_note text,
    decided_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT crm_design_task_approval_steps_stage_key_check CHECK ((stage_key = ANY (ARRAY['CEO'::text, 'GENERAL_MANAGER'::text, 'MQ_04'::text, 'MQ_05'::text, 'MARKETING_MANAGER'::text]))),
    CONSTRAINT crm_design_task_approval_steps_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'APPROVED'::text, 'REJECTED'::text]))),
    CONSTRAINT crm_design_task_approval_steps_step_order_check CHECK (((step_order >= 1) AND (step_order <= 5)))
);


--
-- Name: crm_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_orders (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    deal_id uuid,
    start_date date,
    end_date date,
    event_location text,
    invoice_amount numeric(12,2) DEFAULT 0.00,
    project_status text DEFAULT 'Not Confirmed'::text,
    notes text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    event_date date,
    paid_amount numeric(12,2) DEFAULT 0 NOT NULL,
    uninstallation_date date
);


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    head_id uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    name_ar character varying(255),
    job_titles jsonb DEFAULT '[]'::jsonb
);


--
-- Name: document_expiry_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_expiry_notifications (
    id bigint NOT NULL,
    employee_document_id uuid NOT NULL,
    notification_status text NOT NULL,
    recipient_email text NOT NULL,
    expiration_date date NOT NULL,
    days_left integer NOT NULL,
    sent_at timestamp with time zone,
    provider_message_id text,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT document_expiry_notifications_notification_status_check CHECK ((notification_status = ANY (ARRAY['Expires Soon'::text, 'Expired'::text])))
);


--
-- Name: document_expiry_notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.document_expiry_notifications ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.document_expiry_notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: document_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    doc_type character varying(100) NOT NULL,
    purpose text,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    rejection_reason text,
    CONSTRAINT document_requests_status_check CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'PROCESSED'::character varying, 'REJECTED'::character varying])::text[])))
);


--
-- Name: employee_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    doc_name character varying(255) NOT NULL,
    doc_type character varying(50),
    doc_base64 text,
    created_at timestamp with time zone DEFAULT now(),
    expiration_date date,
    status text DEFAULT 'Active'::text NOT NULL,
    last_notification_status text,
    last_notified_at timestamp with time zone,
    last_notification_error text,
    document_id bigint NOT NULL,
    owner_name text,
    owner_email text,
    responsible_name text,
    responsible_email text,
    notified_30_days boolean DEFAULT true NOT NULL,
    owner_phone text,
    CONSTRAINT employee_documents_notification_status_valid CHECK (((last_notification_status IS NULL) OR (last_notification_status = ANY (ARRAY['Expires Soon'::text, 'Expired'::text])))),
    CONSTRAINT employee_documents_notified_30_days_true CHECK ((notified_30_days = true)),
    CONSTRAINT employee_documents_status_valid CHECK ((status = ANY (ARRAY['Active'::text, 'Expires Soon'::text, 'Expired'::text])))
);


--
-- Name: COLUMN employee_documents.notified_30_days; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employee_documents.notified_30_days IS 'Internal expiry-notification automation flag. Hidden from the employee document directory UI.';


--
-- Name: employee_documents_document_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_documents_document_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_documents_document_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employee_documents_document_id_seq OWNED BY public.employee_documents.document_id;


--
-- Name: employee_loans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_loans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    requested_amount numeric(10,2) NOT NULL,
    monthly_installment numeric(10,2) NOT NULL,
    remaining_balance numeric(10,2) NOT NULL,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT employee_loans_status_check CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'PAID'::character varying])::text[])))
);


--
-- Name: employee_training; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_training (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    course_id uuid,
    status character varying(50) DEFAULT 'ENROLLED'::character varying,
    completion_date date,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT employee_training_status_check CHECK (((status)::text = ANY ((ARRAY['ENROLLED'::character varying, 'IN_PROGRESS'::character varying, 'COMPLETED'::character varying])::text[])))
);


--
-- Name: establishment_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.establishment_settings (
    id integer NOT NULL,
    employer_name_ar character varying(255) DEFAULT 'اسم المنشأة'::character varying,
    employer_name_en character varying(255) DEFAULT 'Establishment Name'::character varying,
    commercial_registration character varying(50),
    unified_establishment_number character varying(50),
    employer_address text,
    employer_city character varying(100),
    employer_region character varying(100),
    authorized_rep_name character varying(255),
    authorized_rep_title character varying(255),
    employer_contact_details text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: establishment_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.establishment_settings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: establishment_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.establishment_settings_id_seq OWNED BY public.establishment_settings.id;


--
-- Name: expense_claims; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expense_claims (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    amount numeric(10,2) NOT NULL,
    category character varying(100),
    description text,
    receipt_url text,
    status character varying(50) DEFAULT 'PENDING'::character varying,
    approved_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT expense_claims_status_check CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying, 'PAID'::character varying])::text[])))
);


--
-- Name: expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expenses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    amount numeric(10,2) NOT NULL,
    description text,
    receipt_base64 text,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    rejection_reason text,
    CONSTRAINT expenses_status_check CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying])::text[])))
);


--
-- Name: goals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    progress integer DEFAULT 0,
    target_date date,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT goals_progress_check CHECK (((progress >= 0) AND (progress <= 100)))
);


--
-- Name: hr_suite_beta_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hr_suite_beta_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    category text NOT NULL,
    title text NOT NULL,
    title_ar text,
    employee_id uuid,
    owner_id uuid,
    status text DEFAULT 'DRAFT'::text NOT NULL,
    priority text DEFAULT 'MEDIUM'::text NOT NULL,
    due_date date,
    amount numeric(14,2),
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by uuid DEFAULT auth.uid(),
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT hr_suite_beta_items_amount_check CHECK (((amount IS NULL) OR (amount >= (0)::numeric))),
    CONSTRAINT hr_suite_beta_items_category_check CHECK ((category = ANY (ARRAY['RECRUITMENT'::text, 'ONBOARDING'::text, 'LEAVE'::text, 'PAYROLL'::text, 'COMPLIANCE'::text, 'OFFBOARDING'::text]))),
    CONSTRAINT hr_suite_beta_items_priority_check CHECK ((priority = ANY (ARRAY['LOW'::text, 'MEDIUM'::text, 'HIGH'::text, 'CRITICAL'::text]))),
    CONSTRAINT hr_suite_beta_items_status_check CHECK ((status = ANY (ARRAY['DRAFT'::text, 'OPEN'::text, 'IN_PROGRESS'::text, 'BLOCKED'::text, 'READY'::text, 'COMPLETED'::text, 'ARCHIVED'::text]))),
    CONSTRAINT hr_suite_beta_items_title_check CHECK ((btrim(title) <> ''::text))
);


--
-- Name: jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    department_id uuid,
    status character varying(50) DEFAULT 'OPEN'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT jobs_status_check CHECK (((status)::text = ANY ((ARRAY['OPEN'::character varying, 'CLOSED'::character varying, 'DRAFT'::character varying])::text[])))
);


--
-- Name: leave_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_requests (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    leave_type character varying(50) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    reason text,
    status character varying(20) DEFAULT 'PENDING'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    short_leave_reason text,
    short_leave_duration_minutes integer,
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    rejection_reason text,
    CONSTRAINT leave_requests_status_check CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'APPROVED'::character varying, 'REJECTED'::character varying])::text[])))
);


--
-- Name: login_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.login_attempts (
    email text NOT NULL,
    attempts integer DEFAULT 0,
    locked_until timestamp with time zone
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sender_id uuid NOT NULL,
    receiver_id uuid NOT NULL,
    content text NOT NULL,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: monthly_sales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.monthly_sales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    month_year character varying(7) NOT NULL,
    actual_sales_amount numeric(10,2) DEFAULT 0.00 NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    message text NOT NULL,
    is_read boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    event_type text,
    task_id uuid,
    actor_id uuid,
    action_url text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp with time zone,
    push_sent_at timestamp with time zone
);


--
-- Name: office_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.office_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    office_latitude double precision NOT NULL,
    office_longitude double precision NOT NULL,
    radius_meters double precision DEFAULT 100 NOT NULL
);


--
-- Name: payroll; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid,
    month_year text NOT NULL,
    net_pay numeric(10,2) DEFAULT 0 NOT NULL,
    overtime_pay numeric(10,2) DEFAULT 0 NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    base_salary numeric(10,2) DEFAULT 0.00,
    commission_amount numeric(10,2) DEFAULT 0.00,
    loan_deduction numeric(10,2) DEFAULT 0.00,
    absence_deduction numeric(10,2) DEFAULT 0.00,
    adjustments_total numeric(10,2) DEFAULT 0.00,
    is_final_settlement boolean DEFAULT false,
    eos_amount numeric(10,2) DEFAULT 0.00
);


--
-- Name: payroll_adjustments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_adjustments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    month_year character varying(7) NOT NULL,
    amount numeric(10,2) NOT NULL,
    reason text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: payroll_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_settings (
    id integer DEFAULT 1 NOT NULL,
    is_overtime_enabled boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: performance_goals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.performance_goals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    due_date date NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying,
    rating integer,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT performance_goals_rating_check CHECK (((rating >= 1) AND (rating <= 5))),
    CONSTRAINT performance_goals_status_check CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'COMPLETED'::character varying, 'OVERDUE'::character varying])::text[])))
);


--
-- Name: performance_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.performance_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    review_period character varying(50),
    rating integer,
    comments text,
    status character varying(50) DEFAULT 'DRAFT'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT performance_reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5))),
    CONSTRAINT performance_reviews_status_check CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'PUBLISHED'::character varying, 'ACKNOWLEDGED'::character varying])::text[])))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    role character varying(20) DEFAULT 'EMPLOYEE'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    manager_id uuid,
    base_salary numeric(10,2) DEFAULT 3000.00,
    annual_leave_allowance integer DEFAULT 30,
    sick_leave_allowance integer DEFAULT 10,
    job_title character varying(100),
    full_name character varying(255),
    iqama_number character varying(50),
    phone_number character varying(50),
    emp_index integer NOT NULL,
    avatar_url text,
    last_login timestamp with time zone,
    birth_date date,
    department_id uuid,
    is_active boolean DEFAULT true,
    display_name character varying(100),
    task_email_notifications boolean DEFAULT true NOT NULL,
    nationality character varying(30) DEFAULT 'Saudi'::character varying,
    display_name_ar character varying(100),
    hire_date date,
    monthly_sales_target numeric(10,2) DEFAULT 0.00,
    job_title_ar character varying(255),
    employee_id character varying(50),
    CONSTRAINT profiles_role_check CHECK (((role)::text = ANY ((ARRAY['ADMIN'::character varying, 'MANAGER'::character varying, 'SUPERVISOR'::character varying, 'EMPLOYEE'::character varying])::text[])))
);


--
-- Name: profiles_emp_index_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.profiles_emp_index_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: profiles_emp_index_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.profiles_emp_index_seq OWNED BY public.profiles.emp_index;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_name character varying(255) NOT NULL,
    project_type character varying(255) NOT NULL,
    description text,
    assigned_people uuid[],
    project_category character varying(50),
    project_tags text[],
    created_at timestamp with time zone DEFAULT now(),
    deal_id uuid,
    client_id uuid,
    event_date date,
    start_date date,
    end_date date,
    uninstallation_date date,
    event_location text,
    project_amount numeric(12,2) DEFAULT 0 NOT NULL,
    paid_amount numeric(12,2) DEFAULT 0 NOT NULL,
    project_status text DEFAULT 'Not Confirmed'::text NOT NULL,
    source text DEFAULT 'MANUAL'::text NOT NULL,
    order_employee_id uuid,
    event_start_time time without time zone,
    installation_time timestamp without time zone,
    uninstallation_time timestamp without time zone,
    client_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    event_location_text text,
    installation_type text,
    equipment jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_by uuid,
    project_manager_id uuid,
    lifecycle_status text DEFAULT 'PLANNING'::text NOT NULL,
    health_status text DEFAULT 'ON_TRACK'::text NOT NULL,
    priority text DEFAULT 'MEDIUM'::text NOT NULL,
    progress_percent integer DEFAULT 0 NOT NULL,
    budget_amount numeric(14,2) DEFAULT 0 NOT NULL,
    actual_cost numeric(14,2) DEFAULT 0 NOT NULL,
    client_name text,
    milestones jsonb DEFAULT '[]'::jsonb NOT NULL,
    risks jsonb DEFAULT '[]'::jsonb NOT NULL,
    last_update text,
    last_update_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT projects_health_status_check CHECK ((health_status = ANY (ARRAY['ON_TRACK'::text, 'AT_RISK'::text, 'OFF_TRACK'::text]))),
    CONSTRAINT projects_installation_type_check CHECK (((installation_type IS NULL) OR (installation_type = ANY (ARRAY['INDOOR'::text, 'OUTDOOR'::text, 'INDOOR_OUTDOOR'::text])))),
    CONSTRAINT projects_lifecycle_status_check CHECK ((lifecycle_status = ANY (ARRAY['PLANNING'::text, 'ACTIVE'::text, 'ON_HOLD'::text, 'COMPLETED'::text, 'CANCELLED'::text]))),
    CONSTRAINT projects_milestones_array_check CHECK ((jsonb_typeof(milestones) = 'array'::text)),
    CONSTRAINT projects_priority_check CHECK ((priority = ANY (ARRAY['LOW'::text, 'MEDIUM'::text, 'HIGH'::text, 'CRITICAL'::text]))),
    CONSTRAINT projects_progress_percent_check CHECK (((progress_percent >= 0) AND (progress_percent <= 100))),
    CONSTRAINT projects_project_category_check CHECK (((project_category)::text = ANY ((ARRAY['Startup'::character varying, 'Enterprise'::character varying])::text[]))),
    CONSTRAINT projects_risks_array_check CHECK ((jsonb_typeof(risks) = 'array'::text))
);


--
-- Name: COLUMN projects.installation_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.projects.installation_time IS 'Local installation date and time captured when a deal is moved to Won.';


--
-- Name: COLUMN projects.uninstallation_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.projects.uninstallation_time IS 'Local uninstallation date and time captured when a deal is moved to Won.';


--
-- Name: push_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth_key text NOT NULL,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: recognitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recognitions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    from_employee_id uuid NOT NULL,
    to_employee_id uuid NOT NULL,
    message text NOT NULL,
    points integer DEFAULT 10,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: released_payslips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.released_payslips (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid,
    employee_name character varying(255) NOT NULL,
    month_year character varying(7) NOT NULL,
    base_salary numeric DEFAULT 0,
    commission numeric DEFAULT 0,
    overtime_pay numeric DEFAULT 0,
    deductions numeric DEFAULT 0,
    net_pay numeric DEFAULT 0,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now())
);


--
-- Name: reminders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reminders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    due_date timestamp with time zone NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    recurrence_type text DEFAULT 'NONE'::text NOT NULL,
    recurrence_interval integer DEFAULT 1 NOT NULL,
    last_notified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT reminders_recurrence_interval_check CHECK (((recurrence_interval >= 1) AND (recurrence_interval <= 365))),
    CONSTRAINT reminders_recurrence_type_check CHECK ((recurrence_type = ANY (ARRAY['NONE'::text, 'DAILY'::text, 'WEEKLY'::text, 'MONTHLY'::text, 'CUSTOM'::text]))),
    CONSTRAINT reminders_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text])))
);


--
-- Name: request_approval_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_approval_steps (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workflow_id uuid NOT NULL,
    step_order integer NOT NULL,
    stage_key text NOT NULL,
    approver_id uuid NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    decision_note text,
    decided_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT request_approval_steps_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'APPROVED'::text, 'REJECTED'::text])))
);


--
-- Name: request_approval_workflows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_approval_workflows (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    source_table text NOT NULL,
    source_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    request_type text NOT NULL,
    is_financial boolean DEFAULT false NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    current_step integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    archived_at timestamp with time zone,
    rejected_by uuid,
    rejection_reason text,
    CONSTRAINT request_approval_workflows_source_table_check CHECK ((source_table = ANY (ARRAY['requests'::text, 'leave_requests'::text, 'document_requests'::text, 'expenses'::text]))),
    CONSTRAINT request_approval_workflows_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'APPROVED'::text, 'REJECTED'::text])))
);


--
-- Name: requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid,
    request_type text NOT NULL,
    leave_type text,
    status text DEFAULT 'Pending'::text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    loan_amount numeric(14,2),
    number_of_days integer,
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    rejection_reason text
);


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role character varying NOT NULL,
    allowed_pages jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: shifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shifts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone NOT NULL,
    location character varying(255),
    role character varying(100),
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: survey_responses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.survey_responses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    survey_id uuid,
    employee_id uuid,
    rating integer,
    comment text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT survey_responses_rating_check CHECK (((rating >= 1) AND (rating <= 10)))
);


--
-- Name: surveys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.surveys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: system_translations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_translations (
    trans_key character varying(255) NOT NULL,
    trans_en text,
    trans_ar text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: task_email_outbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_email_outbox (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    notification_id uuid,
    recipient_id uuid NOT NULL,
    recipient_email text NOT NULL,
    subject text NOT NULL,
    message text NOT NULL,
    action_url text,
    status text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    comment_text text,
    attachment_links jsonb DEFAULT '[]'::jsonb NOT NULL,
    task_id uuid,
    always_send boolean DEFAULT false NOT NULL,
    context_type text DEFAULT 'TASK'::text NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT task_email_outbox_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: task_employee_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.task_employee_access_grants (
    viewer_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    granted_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT task_employee_access_different_people CHECK ((viewer_id <> subject_id))
);


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    assignee_id uuid,
    created_by uuid NOT NULL,
    due_date date,
    status character varying(20) DEFAULT 'TODO'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    priority character varying(20) DEFAULT 'medium'::character varying,
    category character varying(50) DEFAULT 'Work'::character varying,
    title_i18n jsonb DEFAULT '{}'::jsonb,
    description_i18n jsonb DEFAULT '{}'::jsonb,
    updated_at timestamp with time zone DEFAULT now(),
    start_date date,
    end_date date,
    estimated_time character varying(100),
    visibility character varying(20) DEFAULT 'public'::character varying,
    project_id uuid,
    tags text[],
    attachments jsonb DEFAULT '[]'::jsonb,
    visible_to uuid[],
    content_type character varying(255),
    source_link text,
    upload_link text,
    department character varying(255),
    sub_type character varying(255),
    watchers uuid[] DEFAULT '{}'::uuid[],
    parent_task_id uuid,
    supervisor_id uuid,
    marketing_department text,
    content_links text[] DEFAULT '{}'::text[] NOT NULL,
    submission_links text[] DEFAULT '{}'::text[] NOT NULL,
    delivery_status text,
    task_list_id uuid,
    assignee_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    repeat_type text DEFAULT 'NONE'::text NOT NULL,
    repeat_interval integer DEFAULT 1 NOT NULL,
    archived_at timestamp with time zone,
    notify_via_email boolean DEFAULT false NOT NULL,
    crm_deal_id uuid,
    crm_workflow_kind text,
    completion_requested_by uuid,
    completion_requested_at timestamp with time zone,
    completion_approved_by uuid,
    completion_approved_at timestamp with time zone,
    CONSTRAINT tasks_crm_workflow_kind_check CHECK (((crm_workflow_kind IS NULL) OR (crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'::text))),
    CONSTRAINT tasks_delivery_status_check CHECK (((delivery_status IS NULL) OR (delivery_status = ANY (ARRAY['Approved'::text, 'Edit needed'::text])))),
    CONSTRAINT tasks_marketing_department_check CHECK (((marketing_department IS NULL) OR (marketing_department = ANY (ARRAY['Muqamsa'::text, 'Muqam.party'::text, 'Coffee Corner'::text, 'Main'::text, 'Party'::text])))),
    CONSTRAINT tasks_priority_check CHECK (((priority)::text = ANY ((ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying, 'urgent'::character varying])::text[]))),
    CONSTRAINT tasks_repeat_interval_check CHECK ((repeat_interval > 0)),
    CONSTRAINT tasks_repeat_type_check CHECK ((repeat_type = ANY (ARRAY['NONE'::text, 'DAILY'::text, 'WEEKLY'::text, 'MONTHLY'::text]))),
    CONSTRAINT tasks_status_check CHECK (((status)::text = ANY ((ARRAY['todo'::character varying, 'in_progress'::character varying, 'review'::character varying, 'completed'::character varying, 'Pending Approval'::character varying, 'Approved'::character varying, 'Rejected'::character varying])::text[]))),
    CONSTRAINT tasks_visibility_check CHECK (((visibility)::text = ANY ((ARRAY['public'::character varying, 'private'::character varying, 'team'::character varying])::text[])))
);


--
-- Name: COLUMN tasks.source_link; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tasks.source_link IS 'Optional shared URL for regular tasks, or the primary source URL for design tasks.';


--
-- Name: COLUMN tasks.notify_via_email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.tasks.notify_via_email IS 'True only when the task creator explicitly selected Notify via email during creation.';


--
-- Name: time_punches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_punches (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    punch_time timestamp with time zone DEFAULT now(),
    punch_type character varying(10),
    created_at timestamp with time zone DEFAULT now(),
    latitude double precision,
    longitude double precision,
    CONSTRAINT time_punches_punch_type_check CHECK (((punch_type)::text = ANY ((ARRAY['IN'::character varying, 'OUT'::character varying])::text[])))
);


--
-- Name: training_courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.training_courses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    is_mandatory boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_permissions (
    user_id uuid NOT NULL,
    allowed_pages jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: webhooks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhooks (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    url text NOT NULL,
    event_type text NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: commission_tiers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_tiers ALTER COLUMN id SET DEFAULT nextval('public.commission_tiers_id_seq'::regclass);


--
-- Name: contract_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_settings ALTER COLUMN id SET DEFAULT nextval('public.contract_settings_id_seq'::regclass);


--
-- Name: employee_documents document_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents ALTER COLUMN document_id SET DEFAULT nextval('public.employee_documents_document_id_seq'::regclass);


--
-- Name: establishment_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.establishment_settings ALTER COLUMN id SET DEFAULT nextval('public.establishment_settings_id_seq'::regclass);


--
-- Name: profiles emp_index; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles ALTER COLUMN emp_index SET DEFAULT nextval('public.profiles_emp_index_seq'::regclass);


--
-- Name: absences absences_employee_id_date_of_absence_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.absences
    ADD CONSTRAINT absences_employee_id_date_of_absence_key UNIQUE (employee_id, date_of_absence);


--
-- Name: absences absences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.absences
    ADD CONSTRAINT absences_pkey PRIMARY KEY (id);


--
-- Name: admin_password_reset_audit admin_password_reset_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_password_reset_audit
    ADD CONSTRAINT admin_password_reset_audit_pkey PRIMARY KEY (id);


--
-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- Name: attendance attendance_order_location_required; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.attendance
    ADD CONSTRAINT attendance_order_location_required CHECK ((((clock_out_type)::text IS DISTINCT FROM 'ORDER'::text) OR ((order_location_latitude IS NOT NULL) AND (order_location_longitude IS NOT NULL) AND (order_location_shared_at IS NOT NULL)))) NOT VALID;


--
-- Name: attendance attendance_order_photo_required; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.attendance
    ADD CONSTRAINT attendance_order_photo_required CHECK ((((clock_out_type)::text IS DISTINCT FROM 'ORDER'::text) OR (order_location_photo_path IS NOT NULL))) NOT VALID;


--
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: candidates candidates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.candidates
    ADD CONSTRAINT candidates_pkey PRIMARY KEY (id);


--
-- Name: commission_tiers commission_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_tiers
    ADD CONSTRAINT commission_tiers_pkey PRIMARY KEY (id);


--
-- Name: community_chat community_chat_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_chat
    ADD CONSTRAINT community_chat_pkey PRIMARY KEY (id);


--
-- Name: contract_documents contract_documents_contract_id_file_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_documents
    ADD CONSTRAINT contract_documents_contract_id_file_url_key UNIQUE (contract_id, file_url);


--
-- Name: contract_documents contract_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_documents
    ADD CONSTRAINT contract_documents_pkey PRIMARY KEY (id);


--
-- Name: contract_print_requests contract_print_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_print_requests
    ADD CONSTRAINT contract_print_requests_pkey PRIMARY KEY (id);


--
-- Name: contract_settings contract_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_settings
    ADD CONSTRAINT contract_settings_pkey PRIMARY KEY (id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);


--
-- Name: crm_clients crm_clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_clients
    ADD CONSTRAINT crm_clients_pkey PRIMARY KEY (id);


--
-- Name: crm_deal_activity crm_deal_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_activity
    ADD CONSTRAINT crm_deal_activity_pkey PRIMARY KEY (id);


--
-- Name: crm_deal_approval_steps crm_deal_approval_steps_deal_id_stage_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_approval_steps
    ADD CONSTRAINT crm_deal_approval_steps_deal_id_stage_key_key UNIQUE (deal_id, stage_key);


--
-- Name: crm_deal_approval_steps crm_deal_approval_steps_deal_id_step_order_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_approval_steps
    ADD CONSTRAINT crm_deal_approval_steps_deal_id_step_order_key UNIQUE (deal_id, step_order);


--
-- Name: crm_deal_approval_steps crm_deal_approval_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_approval_steps
    ADD CONSTRAINT crm_deal_approval_steps_pkey PRIMARY KEY (id);


--
-- Name: crm_deal_attachments crm_deal_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_attachments
    ADD CONSTRAINT crm_deal_attachments_pkey PRIMARY KEY (id);


--
-- Name: crm_deals crm_deals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deals
    ADD CONSTRAINT crm_deals_pkey PRIMARY KEY (id);


--
-- Name: crm_design_task_approval_steps crm_design_task_approval_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_design_task_approval_steps
    ADD CONSTRAINT crm_design_task_approval_steps_pkey PRIMARY KEY (id);


--
-- Name: crm_design_task_approval_steps crm_design_task_approval_steps_task_id_stage_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_design_task_approval_steps
    ADD CONSTRAINT crm_design_task_approval_steps_task_id_stage_key_key UNIQUE (task_id, stage_key);


--
-- Name: crm_orders crm_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_orders
    ADD CONSTRAINT crm_orders_pkey PRIMARY KEY (id);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: document_expiry_notifications document_expiry_notifications_employee_document_id_notifica_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_expiry_notifications
    ADD CONSTRAINT document_expiry_notifications_employee_document_id_notifica_key UNIQUE (employee_document_id, notification_status, recipient_email, expiration_date);


--
-- Name: document_expiry_notifications document_expiry_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_expiry_notifications
    ADD CONSTRAINT document_expiry_notifications_pkey PRIMARY KEY (id);


--
-- Name: document_requests document_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_requests
    ADD CONSTRAINT document_requests_pkey PRIMARY KEY (id);


--
-- Name: employee_documents employee_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_pkey PRIMARY KEY (id);


--
-- Name: employee_loans employee_loans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_loans
    ADD CONSTRAINT employee_loans_pkey PRIMARY KEY (id);


--
-- Name: employee_training employee_training_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_training
    ADD CONSTRAINT employee_training_pkey PRIMARY KEY (id);


--
-- Name: establishment_settings establishment_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.establishment_settings
    ADD CONSTRAINT establishment_settings_pkey PRIMARY KEY (id);


--
-- Name: expense_claims expense_claims_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_claims
    ADD CONSTRAINT expense_claims_pkey PRIMARY KEY (id);


--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- Name: goals goals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goals
    ADD CONSTRAINT goals_pkey PRIMARY KEY (id);


--
-- Name: hr_suite_beta_items hr_suite_beta_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_suite_beta_items
    ADD CONSTRAINT hr_suite_beta_items_pkey PRIMARY KEY (id);


--
-- Name: job_titles job_titles_department_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_titles
    ADD CONSTRAINT job_titles_department_id_name_key UNIQUE (department_id, name);


--
-- Name: job_titles job_titles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_titles
    ADD CONSTRAINT job_titles_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- Name: login_attempts login_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.login_attempts
    ADD CONSTRAINT login_attempts_pkey PRIMARY KEY (email);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: monthly_sales monthly_sales_employee_id_month_year_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_sales
    ADD CONSTRAINT monthly_sales_employee_id_month_year_key UNIQUE (employee_id, month_year);


--
-- Name: monthly_sales monthly_sales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_sales
    ADD CONSTRAINT monthly_sales_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: office_settings office_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.office_settings
    ADD CONSTRAINT office_settings_pkey PRIMARY KEY (id);


--
-- Name: payroll_adjustments payroll_adjustments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_pkey PRIMARY KEY (id);


--
-- Name: payroll payroll_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll
    ADD CONSTRAINT payroll_pkey PRIMARY KEY (id);


--
-- Name: payroll_settings payroll_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_settings
    ADD CONSTRAINT payroll_settings_pkey PRIMARY KEY (id);


--
-- Name: performance_goals performance_goals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.performance_goals
    ADD CONSTRAINT performance_goals_pkey PRIMARY KEY (id);


--
-- Name: performance_reviews performance_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.performance_reviews
    ADD CONSTRAINT performance_reviews_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_employee_id_key UNIQUE (employee_id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: project_todos project_todos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_todos
    ADD CONSTRAINT project_todos_pkey PRIMARY KEY (id);


--
-- Name: project_updates project_updates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_updates
    ADD CONSTRAINT project_updates_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: push_subscriptions push_subscriptions_endpoint_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint);


--
-- Name: push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: recognitions recognitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognitions
    ADD CONSTRAINT recognitions_pkey PRIMARY KEY (id);


--
-- Name: released_payslips released_payslips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.released_payslips
    ADD CONSTRAINT released_payslips_pkey PRIMARY KEY (id);


--
-- Name: reminders reminders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reminders
    ADD CONSTRAINT reminders_pkey PRIMARY KEY (id);


--
-- Name: request_approval_steps request_approval_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_approval_steps
    ADD CONSTRAINT request_approval_steps_pkey PRIMARY KEY (id);


--
-- Name: request_approval_steps request_approval_steps_workflow_id_step_order_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_approval_steps
    ADD CONSTRAINT request_approval_steps_workflow_id_step_order_key UNIQUE (workflow_id, step_order);


--
-- Name: request_approval_workflows request_approval_workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_approval_workflows
    ADD CONSTRAINT request_approval_workflows_pkey PRIMARY KEY (id);


--
-- Name: request_approval_workflows request_approval_workflows_source_table_source_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_approval_workflows
    ADD CONSTRAINT request_approval_workflows_source_table_source_id_key UNIQUE (source_table, source_id);


--
-- Name: requests requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requests
    ADD CONSTRAINT requests_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role);


--
-- Name: shifts shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_pkey PRIMARY KEY (id);


--
-- Name: survey_responses survey_responses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_responses
    ADD CONSTRAINT survey_responses_pkey PRIMARY KEY (id);


--
-- Name: surveys surveys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.surveys
    ADD CONSTRAINT surveys_pkey PRIMARY KEY (id);


--
-- Name: system_translations system_translations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_translations
    ADD CONSTRAINT system_translations_pkey PRIMARY KEY (trans_key);


--
-- Name: task_activity task_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_activity
    ADD CONSTRAINT task_activity_pkey PRIMARY KEY (id);


--
-- Name: task_attachments task_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_attachments
    ADD CONSTRAINT task_attachments_pkey PRIMARY KEY (id);


--
-- Name: task_comments task_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_comments
    ADD CONSTRAINT task_comments_pkey PRIMARY KEY (id);


--
-- Name: task_email_outbox task_email_outbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_email_outbox
    ADD CONSTRAINT task_email_outbox_pkey PRIMARY KEY (id);


--
-- Name: task_employee_access_grants task_employee_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_employee_access_grants
    ADD CONSTRAINT task_employee_access_grants_pkey PRIMARY KEY (viewer_id, subject_id);


--
-- Name: task_lists task_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_lists
    ADD CONSTRAINT task_lists_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: time_punches time_punches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_punches
    ADD CONSTRAINT time_punches_pkey PRIMARY KEY (id);


--
-- Name: training_courses training_courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.training_courses
    ADD CONSTRAINT training_courses_pkey PRIMARY KEY (id);


--
-- Name: user_permissions user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_pkey PRIMARY KEY (user_id);


--
-- Name: webhooks webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhooks
    ADD CONSTRAINT webhooks_pkey PRIMARY KEY (id);


--
-- Name: admin_password_reset_audit_actor_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX admin_password_reset_audit_actor_created_idx ON public.admin_password_reset_audit USING btree (actor_user_id, created_at DESC);


--
-- Name: admin_password_reset_audit_target_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX admin_password_reset_audit_target_created_idx ON public.admin_password_reset_audit USING btree (target_user_id, created_at DESC);


--
-- Name: contract_documents_contract_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contract_documents_contract_idx ON public.contract_documents USING btree (contract_id, created_at DESC);


--
-- Name: contract_print_requests_manager_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contract_print_requests_manager_status_idx ON public.contract_print_requests USING btree (manager_id, status, requested_at DESC);


--
-- Name: contract_print_requests_one_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contract_print_requests_one_pending_idx ON public.contract_print_requests USING btree (contract_id, employee_id) WHERE (status = 'PENDING'::text);


--
-- Name: contracts_archived_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contracts_archived_idx ON public.contracts USING btree (is_archived, archived_at DESC);


--
-- Name: crm_deal_activity_deal_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX crm_deal_activity_deal_idx ON public.crm_deal_activity USING btree (deal_id, created_at DESC);


--
-- Name: crm_deal_approval_steps_deal_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX crm_deal_approval_steps_deal_idx ON public.crm_deal_approval_steps USING btree (deal_id, step_order);


--
-- Name: crm_deal_attachments_current_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX crm_deal_attachments_current_idx ON public.crm_deal_attachments USING btree (deal_id, category, created_at DESC) WHERE (is_archived = false);


--
-- Name: crm_deal_attachments_deal_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX crm_deal_attachments_deal_idx ON public.crm_deal_attachments USING btree (deal_id, created_at DESC);


--
-- Name: crm_design_task_approval_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX crm_design_task_approval_pending_idx ON public.crm_design_task_approval_steps USING btree (approver_id, status, created_at DESC);


--
-- Name: document_expiry_notifications_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_expiry_notifications_lookup_idx ON public.document_expiry_notifications USING btree (employee_document_id, notification_status, expiration_date);


--
-- Name: document_requests_archived_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_requests_archived_idx ON public.document_requests USING btree (is_archived, archived_at DESC);


--
-- Name: employee_documents_document_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX employee_documents_document_id_idx ON public.employee_documents USING btree (document_id);


--
-- Name: employee_documents_expiration_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX employee_documents_expiration_status_idx ON public.employee_documents USING btree (expiration_date, status) WHERE (expiration_date IS NOT NULL);


--
-- Name: expenses_archived_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expenses_archived_idx ON public.expenses USING btree (is_archived, archived_at DESC);


--
-- Name: hr_suite_beta_items_category_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hr_suite_beta_items_category_status_idx ON public.hr_suite_beta_items USING btree (category, status);


--
-- Name: hr_suite_beta_items_due_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX hr_suite_beta_items_due_date_idx ON public.hr_suite_beta_items USING btree (due_date) WHERE (status <> ALL (ARRAY['COMPLETED'::text, 'ARCHIVED'::text]));


--
-- Name: idx_document_requests_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_document_requests_status_created_at ON public.document_requests USING btree (status, created_at DESC);


--
-- Name: idx_expenses_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_expenses_status_created_at ON public.expenses USING btree (status, created_at DESC);


--
-- Name: idx_leave_requests_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_status_created_at ON public.leave_requests USING btree (status, created_at DESC);


--
-- Name: idx_request_approval_workflows_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_approval_workflows_status_created_at ON public.request_approval_workflows USING btree (status, created_at DESC);


--
-- Name: idx_requests_status_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_requests_status_created_at ON public.requests USING btree (status, created_at DESC);


--
-- Name: idx_tasks_archived_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_archived_at ON public.tasks USING btree (archived_at DESC) WHERE (archived_at IS NOT NULL);


--
-- Name: idx_time_punches_employee_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_time_punches_employee_time ON public.time_punches USING btree (employee_id, punch_time DESC);


--
-- Name: leave_requests_archived_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX leave_requests_archived_idx ON public.leave_requests USING btree (is_archived, archived_at DESC);


--
-- Name: notifications_pending_push_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_pending_push_idx ON public.notifications USING btree (created_at) WHERE (push_sent_at IS NULL);


--
-- Name: profiles_emp_index_unique_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX profiles_emp_index_unique_idx ON public.profiles USING btree (emp_index);


--
-- Name: project_todos_assignees_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_todos_assignees_idx ON public.project_todos USING gin (assignee_ids);


--
-- Name: project_todos_project_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_todos_project_due_idx ON public.project_todos USING btree (project_id, status, due_at);


--
-- Name: project_updates_project_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX project_updates_project_created_idx ON public.project_updates USING btree (project_id, created_at DESC);


--
-- Name: projects_deal_id_unique_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX projects_deal_id_unique_idx ON public.projects USING btree (deal_id) WHERE (deal_id IS NOT NULL);


--
-- Name: projects_health_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_health_status_idx ON public.projects USING btree (health_status);


--
-- Name: projects_lifecycle_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_lifecycle_status_idx ON public.projects USING btree (lifecycle_status);


--
-- Name: projects_manager_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX projects_manager_idx ON public.projects USING btree (project_manager_id);


--
-- Name: reminders_user_due_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reminders_user_due_idx ON public.reminders USING btree (user_id, due_date);


--
-- Name: request_steps_approver_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_steps_approver_idx ON public.request_approval_steps USING btree (approver_id, status);


--
-- Name: request_workflow_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_workflow_employee_idx ON public.request_approval_workflows USING btree (employee_id, created_at DESC);


--
-- Name: requests_archived_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX requests_archived_idx ON public.requests USING btree (is_archived, archived_at DESC);


--
-- Name: task_activity_task_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_activity_task_created_idx ON public.task_activity USING btree (task_id, created_at DESC);


--
-- Name: task_attachments_current_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_attachments_current_idx ON public.task_attachments USING btree (task_id, created_at DESC) WHERE (is_archived = false);


--
-- Name: task_comments_task_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_comments_task_id_idx ON public.task_comments USING btree (task_id, created_at);


--
-- Name: task_comments_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_comments_user_id_idx ON public.task_comments USING btree (user_id);


--
-- Name: task_email_outbox_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_email_outbox_pending_idx ON public.task_email_outbox USING btree (status, created_at);


--
-- Name: task_email_outbox_task_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_email_outbox_task_id_idx ON public.task_email_outbox USING btree (task_id);


--
-- Name: task_lists_department_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_lists_department_id_idx ON public.task_lists USING btree (department_id);


--
-- Name: task_lists_owner_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_lists_owner_id_idx ON public.task_lists USING btree (owner_id);


--
-- Name: task_lists_owner_name_unique_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX task_lists_owner_name_unique_idx ON public.task_lists USING btree (owner_id, lower(btrim(name)));


--
-- Name: task_lists_shared_with_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX task_lists_shared_with_gin_idx ON public.task_lists USING gin (shared_with);


--
-- Name: tasks_crm_deal_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_crm_deal_id_idx ON public.tasks USING btree (crm_deal_id);


--
-- Name: tasks_parent_task_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_parent_task_id_idx ON public.tasks USING btree (parent_task_id);


--
-- Name: tasks_supervisor_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_supervisor_id_idx ON public.tasks USING btree (supervisor_id);


--
-- Name: tasks_task_list_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_task_list_id_idx ON public.tasks USING btree (task_list_id);


--
-- Name: tasks_visible_to_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_visible_to_gin_idx ON public.tasks USING gin (visible_to);


--
-- Name: tasks_watchers_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tasks_watchers_gin_idx ON public.tasks USING gin (watchers);


--
-- Name: contracts archive_ended_employment_contract_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER archive_ended_employment_contract_trigger BEFORE INSERT OR UPDATE OF status ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.archive_ended_employment_contract();


--
-- Name: attendance attendance_coordinates_required; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER attendance_coordinates_required BEFORE INSERT OR UPDATE OF clock_in_time, clock_in_location, clock_out_time, clock_out_location ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.enforce_attendance_coordinates();


--
-- Name: attendance attendance_editor_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER attendance_editor_audit BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.record_attendance_editor();


--
-- Name: contracts contracts_sync_identity_profile; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contracts_sync_identity_profile AFTER INSERT OR UPDATE OF identity_number, employee_phone ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.sync_contract_identity_to_profile();


--
-- Name: crm_deals crm_deal_contact_requirements; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER crm_deal_contact_requirements BEFORE INSERT OR UPDATE ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION public.enforce_crm_deal_contact_requirements();


--
-- Name: crm_deals crm_deals_enforce_workflow_transition; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER crm_deals_enforce_workflow_transition BEFORE INSERT OR UPDATE OF stage, workflow_status, lost_reason ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION public.enforce_deal_workflow_transition();


--
-- Name: tasks crm_design_task_completion_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER crm_design_task_completion_trigger BEFORE UPDATE OF status ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.enforce_crm_design_task_completion();


--
-- Name: tasks crm_design_task_status_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER crm_design_task_status_insert_trigger AFTER INSERT ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.sync_crm_design_task_status();


--
-- Name: tasks crm_design_task_status_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER crm_design_task_status_update_trigger AFTER UPDATE OF status, due_date, crm_deal_id, crm_workflow_kind ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.sync_crm_design_task_status();


--
-- Name: tasks enforce_marketing_design_review_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_marketing_design_review_trigger BEFORE INSERT OR UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.enforce_marketing_design_review();


--
-- Name: tasks enforce_mq07_design_assignment_department_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_mq07_design_assignment_department_trigger BEFORE INSERT OR UPDATE OF assignee_id, assignee_ids, task_list_id, created_by ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.enforce_mq07_design_assignment_department();


--
-- Name: tasks enforce_private_task_list_ownership_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enforce_private_task_list_ownership_trigger BEFORE INSERT OR UPDATE OF task_list_id, created_by, assignee_id, supervisor_id, visibility, visible_to, watchers ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.enforce_private_task_list_ownership();


--
-- Name: hr_suite_beta_items hr_suite_beta_items_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER hr_suite_beta_items_audit BEFORE INSERT OR UPDATE ON public.hr_suite_beta_items FOR EACH ROW EXECUTE FUNCTION public.set_hr_suite_beta_audit();


--
-- Name: tasks inherit_parent_task_access_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inherit_parent_task_access_trigger BEFORE INSERT OR UPDATE OF parent_task_id ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.inherit_parent_task_access();


--
-- Name: tasks notify_task_change_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notify_task_change_trigger AFTER INSERT OR UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.notify_task_change();


--
-- Name: task_comments notify_task_comment_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notify_task_comment_trigger AFTER INSERT ON public.task_comments FOR EACH ROW EXECUTE FUNCTION public.notify_task_comment();


--
-- Name: profiles profiles_assign_employee_number; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER profiles_assign_employee_number BEFORE INSERT ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.assign_profile_employee_number();


--
-- Name: profiles profiles_executive_admin_role; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER profiles_executive_admin_role BEFORE INSERT OR UPDATE OF job_title, role ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.enforce_executive_admin_role();


--
-- Name: project_todos project_todo_notify_assignees; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER project_todo_notify_assignees AFTER INSERT ON public.project_todos FOR EACH ROW EXECUTE FUNCTION public.notify_project_todo_assignees();


--
-- Name: project_updates project_updates_touch_project; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER project_updates_touch_project AFTER INSERT ON public.project_updates FOR EACH ROW EXECUTE FUNCTION public.touch_project_from_update();


--
-- Name: employee_documents protect_employee_document_system_fields_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_employee_document_system_fields_trigger BEFORE UPDATE ON public.employee_documents FOR EACH ROW EXECUTE FUNCTION public.protect_employee_document_system_fields();


--
-- Name: crm_deals protect_lost_crm_deal_edits_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_lost_crm_deal_edits_trigger BEFORE UPDATE ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION public.protect_lost_crm_deal_edits();


--
-- Name: profiles protect_profile_privileged_fields_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_profile_privileged_fields_trigger BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.protect_profile_privileged_fields();


--
-- Name: tasks protect_task_access_fields_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER protect_task_access_fields_trigger BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.protect_task_access_fields();


--
-- Name: document_requests request_workflow_document_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER request_workflow_document_insert AFTER INSERT ON public.document_requests FOR EACH ROW EXECUTE FUNCTION public.request_workflow_after_insert();


--
-- Name: expenses request_workflow_expense_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER request_workflow_expense_insert AFTER INSERT ON public.expenses FOR EACH ROW EXECUTE FUNCTION public.request_workflow_after_insert();


--
-- Name: requests request_workflow_generic_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER request_workflow_generic_insert AFTER INSERT ON public.requests FOR EACH ROW EXECUTE FUNCTION public.request_workflow_after_insert();


--
-- Name: leave_requests request_workflow_leave_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER request_workflow_leave_insert AFTER INSERT ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.request_workflow_after_insert();


--
-- Name: employee_documents set_employee_document_expiry_status_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_employee_document_expiry_status_trigger BEFORE INSERT OR UPDATE OF expiration_date ON public.employee_documents FOR EACH ROW EXECUTE FUNCTION public.set_employee_document_expiry_status();


--
-- Name: profiles sync_department_head_from_manager_title_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sync_department_head_from_manager_title_trigger AFTER INSERT OR UPDATE OF job_title, department_id ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.sync_department_head_from_manager_title();


--
-- Name: tasks task_activity_after_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER task_activity_after_insert AFTER INSERT ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();


--
-- Name: tasks task_activity_after_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER task_activity_after_update AFTER UPDATE OF status, assignee_id, assignee_ids ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();


--
-- Name: tasks task_activity_before_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER task_activity_before_delete BEFORE DELETE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.record_task_activity();


--
-- Name: task_attachments task_attachment_activity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER task_attachment_activity AFTER INSERT OR UPDATE OF is_archived ON public.task_attachments FOR EACH ROW EXECUTE FUNCTION public.record_task_child_activity();


--
-- Name: task_comments task_comment_activity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER task_comment_activity AFTER INSERT OR DELETE OR UPDATE ON public.task_comments FOR EACH ROW EXECUTE FUNCTION public.record_task_child_activity();


--
-- Name: tasks task_status_notification_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER task_status_notification_trigger AFTER UPDATE OF status ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.queue_task_status_notification();


--
-- Name: tasks tasks_apply_creation_defaults; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tasks_apply_creation_defaults BEFORE INSERT ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.apply_task_creation_defaults();


--
-- Name: tasks trg_clean_task_history_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clean_task_history_on_delete BEFORE DELETE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.clean_task_history_on_delete();


--
-- Name: tasks update_tasks_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_tasks_updated_at BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: crm_deal_attachments validate_crm_deal_attachment_metadata; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_crm_deal_attachment_metadata BEFORE INSERT OR UPDATE ON public.crm_deal_attachments FOR EACH ROW EXECUTE FUNCTION public.validate_shared_attachment_metadata();


--
-- Name: requests validate_leave_request_days_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_leave_request_days_trigger BEFORE INSERT OR UPDATE OF request_type, number_of_days ON public.requests FOR EACH ROW EXECUTE FUNCTION public.validate_leave_request_days();


--
-- Name: requests validate_loan_request_amount_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_loan_request_amount_trigger BEFORE INSERT OR UPDATE OF request_type, loan_amount ON public.requests FOR EACH ROW EXECUTE FUNCTION public.validate_loan_request_amount();


--
-- Name: profiles validate_profile_job_title_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_profile_job_title_trigger BEFORE INSERT OR UPDATE OF job_title, department_id ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.validate_profile_job_title();


--
-- Name: leave_requests validate_short_leave_request_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_short_leave_request_trigger BEFORE INSERT OR UPDATE OF leave_type, short_leave_reason, short_leave_duration_minutes ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.validate_short_leave_request();


--
-- Name: task_attachments validate_task_attachment_metadata; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_task_attachment_metadata BEFORE INSERT OR UPDATE ON public.task_attachments FOR EACH ROW EXECUTE FUNCTION public.validate_shared_attachment_metadata();


--
-- Name: tasks validate_task_department_supervisor_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_task_department_supervisor_trigger BEFORE INSERT OR UPDATE OF supervisor_id, created_by ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.validate_task_department_supervisor();


--
-- Name: task_lists validate_task_list_department_access_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER validate_task_list_department_access_trigger BEFORE INSERT OR UPDATE OF owner_id, department_id, visible_to_all, shared_with, can_add_users, can_delete_users ON public.task_lists FOR EACH ROW EXECUTE FUNCTION public.validate_task_list_department_access();


--
-- Name: absences absences_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.absences
    ADD CONSTRAINT absences_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: announcements announcements_admin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES auth.users(id);


--
-- Name: attendance attendance_clock_in_edited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_clock_in_edited_by_fkey FOREIGN KEY (clock_in_edited_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_clock_out_edited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_clock_out_edited_by_fkey FOREIGN KEY (clock_out_edited_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);


--
-- Name: candidates candidates_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.candidates
    ADD CONSTRAINT candidates_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.jobs(id);


--
-- Name: community_chat community_chat_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.community_chat
    ADD CONSTRAINT community_chat_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: contract_documents contract_documents_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_documents
    ADD CONSTRAINT contract_documents_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contracts(id) ON DELETE CASCADE;


--
-- Name: contract_documents contract_documents_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_documents
    ADD CONSTRAINT contract_documents_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: contract_documents contract_documents_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_documents
    ADD CONSTRAINT contract_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: contract_print_requests contract_print_requests_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_print_requests
    ADD CONSTRAINT contract_print_requests_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contracts(id) ON DELETE CASCADE;


--
-- Name: contract_print_requests contract_print_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_print_requests
    ADD CONSTRAINT contract_print_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: contract_print_requests contract_print_requests_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_print_requests
    ADD CONSTRAINT contract_print_requests_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: contracts contracts_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: contracts contracts_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: contracts contracts_previous_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_previous_contract_id_fkey FOREIGN KEY (previous_contract_id) REFERENCES public.contracts(id);


--
-- Name: crm_clients crm_clients_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_clients
    ADD CONSTRAINT crm_clients_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id);


--
-- Name: crm_deal_activity crm_deal_activity_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_activity
    ADD CONSTRAINT crm_deal_activity_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id);


--
-- Name: crm_deal_activity crm_deal_activity_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_activity
    ADD CONSTRAINT crm_deal_activity_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.crm_deals(id) ON DELETE CASCADE;


--
-- Name: crm_deal_approval_steps crm_deal_approval_steps_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_approval_steps
    ADD CONSTRAINT crm_deal_approval_steps_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.profiles(id);


--
-- Name: crm_deal_approval_steps crm_deal_approval_steps_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_approval_steps
    ADD CONSTRAINT crm_deal_approval_steps_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.crm_deals(id) ON DELETE CASCADE;


--
-- Name: crm_deal_attachments crm_deal_attachments_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_attachments
    ADD CONSTRAINT crm_deal_attachments_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: crm_deal_attachments crm_deal_attachments_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_attachments
    ADD CONSTRAINT crm_deal_attachments_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.crm_deals(id) ON DELETE CASCADE;


--
-- Name: crm_deal_attachments crm_deal_attachments_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deal_attachments
    ADD CONSTRAINT crm_deal_attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id);


--
-- Name: crm_deals crm_deals_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deals
    ADD CONSTRAINT crm_deals_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id);


--
-- Name: crm_deals crm_deals_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deals
    ADD CONSTRAINT crm_deals_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.crm_clients(id) ON DELETE CASCADE;


--
-- Name: crm_deals crm_deals_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deals
    ADD CONSTRAINT crm_deals_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: crm_deals crm_deals_design_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_deals
    ADD CONSTRAINT crm_deals_design_task_id_fkey FOREIGN KEY (design_task_id) REFERENCES public.tasks(id) ON DELETE SET NULL;


--
-- Name: crm_design_task_approval_steps crm_design_task_approval_steps_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_design_task_approval_steps
    ADD CONSTRAINT crm_design_task_approval_steps_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.profiles(id);


--
-- Name: crm_design_task_approval_steps crm_design_task_approval_steps_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_design_task_approval_steps
    ADD CONSTRAINT crm_design_task_approval_steps_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.crm_deals(id) ON DELETE CASCADE;


--
-- Name: crm_design_task_approval_steps crm_design_task_approval_steps_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_design_task_approval_steps
    ADD CONSTRAINT crm_design_task_approval_steps_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;


--
-- Name: crm_orders crm_orders_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_orders
    ADD CONSTRAINT crm_orders_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.crm_deals(id) ON DELETE CASCADE;


--
-- Name: departments departments_head_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_head_id_fkey FOREIGN KEY (head_id) REFERENCES public.profiles(id);


--
-- Name: document_expiry_notifications document_expiry_notifications_employee_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_expiry_notifications
    ADD CONSTRAINT document_expiry_notifications_employee_document_id_fkey FOREIGN KEY (employee_document_id) REFERENCES public.employee_documents(id) ON DELETE CASCADE;


--
-- Name: document_requests document_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_requests
    ADD CONSTRAINT document_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: employee_documents employee_documents_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: employee_loans employee_loans_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_loans
    ADD CONSTRAINT employee_loans_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: employee_training employee_training_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_training
    ADD CONSTRAINT employee_training_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.training_courses(id);


--
-- Name: employee_training employee_training_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_training
    ADD CONSTRAINT employee_training_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: expense_claims expense_claims_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_claims
    ADD CONSTRAINT expense_claims_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);


--
-- Name: expense_claims expense_claims_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_claims
    ADD CONSTRAINT expense_claims_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: expenses expenses_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: task_comments fk_task_comments_profiles; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_comments
    ADD CONSTRAINT fk_task_comments_profiles FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: goals goals_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goals
    ADD CONSTRAINT goals_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: hr_suite_beta_items hr_suite_beta_items_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_suite_beta_items
    ADD CONSTRAINT hr_suite_beta_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: hr_suite_beta_items hr_suite_beta_items_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_suite_beta_items
    ADD CONSTRAINT hr_suite_beta_items_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: hr_suite_beta_items hr_suite_beta_items_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_suite_beta_items
    ADD CONSTRAINT hr_suite_beta_items_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: hr_suite_beta_items hr_suite_beta_items_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hr_suite_beta_items
    ADD CONSTRAINT hr_suite_beta_items_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: job_titles job_titles_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_titles
    ADD CONSTRAINT job_titles_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE RESTRICT;


--
-- Name: jobs jobs_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: messages messages_receiver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_receiver_id_fkey FOREIGN KEY (receiver_id) REFERENCES auth.users(id);


--
-- Name: messages messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES auth.users(id);


--
-- Name: monthly_sales monthly_sales_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_sales
    ADD CONSTRAINT monthly_sales_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: notifications notifications_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);


--
-- Name: payroll_adjustments payroll_adjustments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: payroll payroll_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll
    ADD CONSTRAINT payroll_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: performance_goals performance_goals_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.performance_goals
    ADD CONSTRAINT performance_goals_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: performance_reviews performance_reviews_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.performance_reviews
    ADD CONSTRAINT performance_reviews_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: performance_reviews performance_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.performance_reviews
    ADD CONSTRAINT performance_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES auth.users(id);


--
-- Name: profiles profiles_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id);


--
-- Name: profiles profiles_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES auth.users(id);


--
-- Name: project_todos project_todos_completed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_todos
    ADD CONSTRAINT project_todos_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: project_todos project_todos_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_todos
    ADD CONSTRAINT project_todos_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: project_todos project_todos_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_todos
    ADD CONSTRAINT project_todos_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: project_updates project_updates_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_updates
    ADD CONSTRAINT project_updates_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: project_updates project_updates_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_updates
    ADD CONSTRAINT project_updates_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: projects projects_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.crm_clients(id) ON DELETE SET NULL;


--
-- Name: projects projects_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: projects projects_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES public.crm_deals(id) ON DELETE SET NULL;


--
-- Name: projects projects_order_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_order_employee_id_fkey FOREIGN KEY (order_employee_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: projects projects_project_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_project_manager_id_fkey FOREIGN KEY (project_manager_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: push_subscriptions push_subscriptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: recognitions recognitions_from_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognitions
    ADD CONSTRAINT recognitions_from_employee_id_fkey FOREIGN KEY (from_employee_id) REFERENCES auth.users(id);


--
-- Name: recognitions recognitions_to_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recognitions
    ADD CONSTRAINT recognitions_to_employee_id_fkey FOREIGN KEY (to_employee_id) REFERENCES auth.users(id);


--
-- Name: released_payslips released_payslips_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.released_payslips
    ADD CONSTRAINT released_payslips_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: reminders reminders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reminders
    ADD CONSTRAINT reminders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: request_approval_steps request_approval_steps_approver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_approval_steps
    ADD CONSTRAINT request_approval_steps_approver_id_fkey FOREIGN KEY (approver_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: request_approval_steps request_approval_steps_workflow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_approval_steps
    ADD CONSTRAINT request_approval_steps_workflow_id_fkey FOREIGN KEY (workflow_id) REFERENCES public.request_approval_workflows(id) ON DELETE CASCADE;


--
-- Name: request_approval_workflows request_approval_workflows_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_approval_workflows
    ADD CONSTRAINT request_approval_workflows_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: request_approval_workflows request_approval_workflows_rejected_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_approval_workflows
    ADD CONSTRAINT request_approval_workflows_rejected_by_fkey FOREIGN KEY (rejected_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: requests requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.requests
    ADD CONSTRAINT requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: shifts shifts_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: survey_responses survey_responses_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_responses
    ADD CONSTRAINT survey_responses_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES auth.users(id);


--
-- Name: survey_responses survey_responses_survey_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.survey_responses
    ADD CONSTRAINT survey_responses_survey_id_fkey FOREIGN KEY (survey_id) REFERENCES public.surveys(id);


--
-- Name: task_activity task_activity_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_activity
    ADD CONSTRAINT task_activity_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: task_attachments task_attachments_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_attachments
    ADD CONSTRAINT task_attachments_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: task_attachments task_attachments_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_attachments
    ADD CONSTRAINT task_attachments_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;


--
-- Name: task_attachments task_attachments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_attachments
    ADD CONSTRAINT task_attachments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: task_comments task_comments_parent_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_comments
    ADD CONSTRAINT task_comments_parent_comment_id_fkey FOREIGN KEY (parent_comment_id) REFERENCES public.task_comments(id) ON DELETE CASCADE;


--
-- Name: task_comments task_comments_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_comments
    ADD CONSTRAINT task_comments_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;


--
-- Name: task_email_outbox task_email_outbox_notification_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_email_outbox
    ADD CONSTRAINT task_email_outbox_notification_id_fkey FOREIGN KEY (notification_id) REFERENCES public.notifications(id) ON DELETE CASCADE;


--
-- Name: task_email_outbox task_email_outbox_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_email_outbox
    ADD CONSTRAINT task_email_outbox_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: task_email_outbox task_email_outbox_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_email_outbox
    ADD CONSTRAINT task_email_outbox_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;


--
-- Name: task_employee_access_grants task_employee_access_grants_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_employee_access_grants
    ADD CONSTRAINT task_employee_access_grants_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: task_employee_access_grants task_employee_access_grants_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_employee_access_grants
    ADD CONSTRAINT task_employee_access_grants_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: task_employee_access_grants task_employee_access_grants_viewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_employee_access_grants
    ADD CONSTRAINT task_employee_access_grants_viewer_id_fkey FOREIGN KEY (viewer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: task_lists task_lists_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_lists
    ADD CONSTRAINT task_lists_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: task_lists task_lists_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.task_lists
    ADD CONSTRAINT task_lists_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_assignee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES auth.users(id);


--
-- Name: tasks tasks_completion_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_completion_approved_by_fkey FOREIGN KEY (completion_approved_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: tasks tasks_completion_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_completion_requested_by_fkey FOREIGN KEY (completion_requested_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: tasks tasks_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);


--
-- Name: tasks tasks_crm_deal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_crm_deal_id_fkey FOREIGN KEY (crm_deal_id) REFERENCES public.crm_deals(id) ON DELETE SET NULL;


--
-- Name: tasks tasks_parent_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_parent_task_id_fkey FOREIGN KEY (parent_task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE SET NULL;


--
-- Name: tasks tasks_supervisor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_supervisor_id_fkey FOREIGN KEY (supervisor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: tasks tasks_task_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_task_list_id_fkey FOREIGN KEY (task_list_id) REFERENCES public.task_lists(id) ON DELETE SET NULL;


--
-- Name: user_permissions user_permissions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permissions
    ADD CONSTRAINT user_permissions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: profiles Admin and HR can update employee profile photos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin and HR can update employee profile photos" ON public.profiles FOR UPDATE TO authenticated USING (public.can_manage_employee_photos(auth.uid())) WITH CHECK (public.can_manage_employee_photos(auth.uid()));


--
-- Name: contracts Admin view all contracts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admin view all contracts" ON public.contracts TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((upper((profiles.role)::text) = 'ADMIN'::text) OR (upper((profiles.job_title)::text) = 'HR MANAGER'::text)))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((upper((profiles.role)::text) = 'ADMIN'::text) OR (upper((profiles.job_title)::text) = 'HR MANAGER'::text))))));


--
-- Name: expense_claims Admins and Managers view and update expenses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins and Managers view and update expenses" ON public.expense_claims USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'MANAGER'::character varying])::text[]))))));


--
-- Name: payroll Admins can delete payroll; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can delete payroll" ON public.payroll FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'Admin'::text)))));


--
-- Name: system_translations Admins can delete translations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can delete translations" ON public.system_translations FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: webhooks Admins can delete webhooks; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can delete webhooks" ON public.webhooks FOR DELETE USING (true);


--
-- Name: contract_settings Admins can edit contract settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can edit contract settings" ON public.contract_settings USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: establishment_settings Admins can edit establishment settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can edit establishment settings" ON public.establishment_settings USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: audit_logs Admins can insert audit logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert audit logs" ON public.audit_logs FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: notifications Admins can insert notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert notifications" ON public.notifications FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'MANAGER'::character varying])::text[]))))));


--
-- Name: payroll Admins can insert payroll; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert payroll" ON public.payroll FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'Admin'::text)))));


--
-- Name: released_payslips Admins can insert released payslips; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert released payslips" ON public.released_payslips FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (((profiles.role)::text = 'ADMIN'::text) OR ((profiles.job_title)::text ~~* '%manager%'::text))))));


--
-- Name: system_translations Admins can insert translations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert translations" ON public.system_translations FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: webhooks Admins can insert webhooks; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can insert webhooks" ON public.webhooks FOR INSERT WITH CHECK (true);


--
-- Name: performance_goals Admins can manage all goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage all goals" ON public.performance_goals USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: profiles Admins can read all profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can read all profiles" ON public.profiles FOR SELECT USING ((public.get_user_role() = 'ADMIN'::text));


--
-- Name: profiles Admins can update all profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update all profiles" ON public.profiles FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.profiles profiles_1
  WHERE ((profiles_1.id = auth.uid()) AND ((profiles_1.role)::text = 'ADMIN'::text)))));


--
-- Name: payroll Admins can update payroll; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update payroll" ON public.payroll FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'Admin'::text)))));


--
-- Name: system_translations Admins can update translations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update translations" ON public.system_translations FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: webhooks Admins can update webhooks; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can update webhooks" ON public.webhooks FOR UPDATE USING (true);


--
-- Name: payroll Admins can view all payroll; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view all payroll" ON public.payroll FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'Admin'::text)))));


--
-- Name: profiles Admins can view all profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT TO authenticated USING (public.admin_can_read_all_profiles());


--
-- Name: audit_logs Admins can view audit logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view audit logs" ON public.audit_logs FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: webhooks Admins can view webhooks; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view webhooks" ON public.webhooks FOR SELECT USING (true);


--
-- Name: contracts Admins have full access to contracts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins have full access to contracts" ON public.contracts USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: candidates Admins manage candidates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins manage candidates" ON public.candidates USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'MANAGER'::character varying])::text[]))))));


--
-- Name: training_courses Admins manage courses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins manage courses" ON public.training_courses USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: jobs Admins manage jobs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins manage jobs" ON public.jobs USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'MANAGER'::character varying])::text[]))))));


--
-- Name: performance_reviews Admins manage reviews; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins manage reviews" ON public.performance_reviews USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: surveys Admins manage surveys; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins manage surveys" ON public.surveys USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: employee_training Admins view all training; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins view all training" ON public.employee_training FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: survey_responses Admins view responses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins view responses" ON public.survey_responses FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: projects Admins, Sales and Marketing can delete projects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins, Sales and Marketing can delete projects" ON public.projects FOR DELETE USING ((EXISTS ( SELECT 1
   FROM (public.profiles
     LEFT JOIN public.departments ON ((profiles.department_id = departments.id)))
  WHERE ((profiles.id = auth.uid()) AND (((profiles.role)::text ~~* '%ADMIN%'::text) OR ((profiles.role)::text ~~* '%SALES%'::text) OR ((profiles.role)::text ~~* '%MARKETING%'::text) OR ((profiles.job_title)::text ~~* '%SALES%'::text) OR ((profiles.job_title)::text ~~* '%MARKETING%'::text) OR ((profiles.role)::text ~~* '%مبيعات%'::text) OR ((profiles.role)::text ~~* '%تسويق%'::text) OR ((profiles.job_title)::text ~~* '%مبيعات%'::text) OR ((profiles.job_title)::text ~~* '%تسويق%'::text) OR (departments.name ~~* '%sales%'::text) OR (departments.name ~~* '%marketing%'::text) OR (departments.name ~~* '%مبيعات%'::text) OR (departments.name ~~* '%تسويق%'::text))))));


--
-- Name: shifts Admins/Managers manage shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins/Managers manage shifts" ON public.shifts USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'MANAGER'::character varying])::text[]))))));


--
-- Name: goals Admins/Managers view goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins/Managers view goals" ON public.goals FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'MANAGER'::character varying])::text[]))))));


--
-- Name: role_permissions Allow admins to modify role permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow admins to modify role permissions" ON public.role_permissions USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SYSTEM ADMIN'::character varying, 'OWNER'::character varying])::text[])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SYSTEM ADMIN'::character varying, 'OWNER'::character varying])::text[]))))));


--
-- Name: user_permissions Allow admins to modify user permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow admins to modify user permissions" ON public.user_permissions USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SYSTEM ADMIN'::character varying, 'OWNER'::character varying])::text[])))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SYSTEM ADMIN'::character varying, 'OWNER'::character varying])::text[]))))));


--
-- Name: absences Allow all access to absences for authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all access to absences for authenticated users" ON public.absences USING ((auth.role() = 'authenticated'::text));


--
-- Name: commission_tiers Allow all access to commission_tiers for authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all access to commission_tiers for authenticated users" ON public.commission_tiers USING ((auth.role() = 'authenticated'::text));


--
-- Name: employee_loans Allow all access to employee_loans for authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all access to employee_loans for authenticated users" ON public.employee_loans USING ((auth.role() = 'authenticated'::text));


--
-- Name: monthly_sales Allow all access to monthly_sales for authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all access to monthly_sales for authenticated users" ON public.monthly_sales USING ((auth.role() = 'authenticated'::text));


--
-- Name: payroll_adjustments Allow all access to payroll_adjustments for authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all access to payroll_adjustments for authenticated users" ON public.payroll_adjustments USING ((auth.role() = 'authenticated'::text));


--
-- Name: payroll_settings Allow all access to payroll_settings for authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all access to payroll_settings for authenticated users" ON public.payroll_settings USING ((auth.role() = 'authenticated'::text));


--
-- Name: time_punches Allow anonymous inserts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow anonymous inserts" ON public.time_punches FOR INSERT WITH CHECK (true);


--
-- Name: announcements Allow anonymous selects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow anonymous selects" ON public.announcements FOR SELECT USING (true);


--
-- Name: time_punches Allow anonymous selects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow anonymous selects" ON public.time_punches FOR SELECT USING (true);


--
-- Name: role_permissions Allow authenticated users to read role permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated users to read role permissions" ON public.role_permissions FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: user_permissions Allow authenticated users to read their own permissions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow authenticated users to read their own permissions" ON public.user_permissions FOR SELECT USING (((auth.uid() = user_id) OR (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SYSTEM ADMIN'::character varying, 'OWNER'::character varying])::text[])))))));


--
-- Name: community_chat Anyone can post in chat; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone can post in chat" ON public.community_chat FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: login_attempts Anyone can read login attempts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone can read login attempts" ON public.login_attempts FOR SELECT USING (true);


--
-- Name: announcements Anyone can view announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone can view announcements" ON public.announcements FOR SELECT USING (true);


--
-- Name: community_chat Anyone can view chat; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone can view chat" ON public.community_chat FOR SELECT USING (true);


--
-- Name: system_translations Anyone can view translations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone can view translations" ON public.system_translations FOR SELECT USING (true);


--
-- Name: contracts Archived contracts are visible to contract managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Archived contracts are visible to contract managers" ON public.contracts FOR SELECT USING (((is_archived = true) AND (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.is_active IS DISTINCT FROM false) AND ((upper((COALESCE(profiles.role, ''::character varying))::text) = 'ADMIN'::text) OR (upper((COALESCE(profiles.job_title, ''::character varying))::text) = 'HR MANAGER'::text)))))));


--
-- Name: crm_deal_activity Authenticated users can add deal activity; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can add deal activity" ON public.crm_deal_activity FOR INSERT TO authenticated WITH CHECK ((actor_id = auth.uid()));


--
-- Name: crm_deal_attachments Authenticated users can add deal attachments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can add deal attachments" ON public.crm_deal_attachments FOR INSERT TO authenticated WITH CHECK ((uploaded_by = auth.uid()));


--
-- Name: crm_deal_activity Authenticated users can view deal activity; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can view deal activity" ON public.crm_deal_activity FOR SELECT TO authenticated USING (true);


--
-- Name: crm_deal_approval_steps Authenticated users can view deal approvals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can view deal approvals" ON public.crm_deal_approval_steps FOR SELECT TO authenticated USING (true);


--
-- Name: crm_deal_attachments Authenticated users can view deal attachments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can view deal attachments" ON public.crm_deal_attachments FOR SELECT TO authenticated USING (true);


--
-- Name: profiles Contract managers can update employee profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Contract managers can update employee profiles" ON public.profiles FOR UPDATE TO authenticated USING (public.can_manage_employee_contracts(auth.uid())) WITH CHECK (public.can_manage_employee_contracts(auth.uid()));


--
-- Name: contract_documents Contract parties can view contract documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Contract parties can view contract documents" ON public.contract_documents FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles viewer
  WHERE ((viewer.id = auth.uid()) AND ((upper((COALESCE(viewer.role, ''::character varying))::text) = ANY (ARRAY['ADMIN'::text, 'ROLE_SYSTEM_ADMIN'::text, 'SYSTEM_ADMIN'::text])) OR (upper(TRIM(BOTH FROM COALESCE(viewer.job_title, ''::character varying))) = 'HR MANAGER'::text)))))));


--
-- Name: departments Departments are deletable by admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Departments are deletable by admins" ON public.departments FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SUPER_ADMIN'::character varying, 'HR_MANAGER'::character varying])::text[]))))));


--
-- Name: departments Departments are insertable by admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Departments are insertable by admins" ON public.departments FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SUPER_ADMIN'::character varying, 'HR_MANAGER'::character varying])::text[]))))));


--
-- Name: departments Departments are updatable by admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Departments are updatable by admins" ON public.departments FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SUPER_ADMIN'::character varying, 'HR_MANAGER'::character varying])::text[]))))));


--
-- Name: departments Departments are viewable by all authenticated users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Departments are viewable by all authenticated users" ON public.departments FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: profiles Employees can update their own profile photo; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can update their own profile photo" ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));


--
-- Name: contracts Employees can view own contract; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view own contract" ON public.contracts FOR SELECT TO authenticated USING ((employee_id = auth.uid()));


--
-- Name: contracts Employees can view their own contracts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view their own contracts" ON public.contracts FOR SELECT USING ((auth.uid() = employee_id));


--
-- Name: performance_goals Employees can view their own goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view their own goals" ON public.performance_goals FOR SELECT USING ((auth.uid() = employee_id));


--
-- Name: recognitions Employees give recognition; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees give recognition" ON public.recognitions FOR INSERT WITH CHECK ((auth.uid() = from_employee_id));


--
-- Name: expense_claims Employees insert own expenses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees insert own expenses" ON public.expense_claims FOR INSERT WITH CHECK ((auth.uid() = employee_id));


--
-- Name: survey_responses Employees insert responses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees insert responses" ON public.survey_responses FOR INSERT WITH CHECK (((auth.uid() = employee_id) OR (employee_id IS NULL)));


--
-- Name: goals Employees manage own goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees manage own goals" ON public.goals USING ((auth.uid() = employee_id));


--
-- Name: employee_training Employees manage own training; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees manage own training" ON public.employee_training USING ((auth.uid() = employee_id));


--
-- Name: contract_print_requests Employees request their own contract print; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees request their own contract print" ON public.contract_print_requests FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) AND (status = 'PENDING'::text)));


--
-- Name: contract_print_requests Employees view own contract print requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees view own contract print requests" ON public.contract_print_requests FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (manager_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (upper((COALESCE(p.role, ''::character varying))::text) = 'ADMIN'::text))))));


--
-- Name: expense_claims Employees view own expenses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees view own expenses" ON public.expense_claims FOR SELECT USING ((auth.uid() = employee_id));


--
-- Name: shifts Employees view own shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees view own shifts" ON public.shifts FOR SELECT USING ((auth.uid() = employee_id));


--
-- Name: contract_settings Everyone can view contract settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Everyone can view contract settings" ON public.contract_settings FOR SELECT USING (true);


--
-- Name: establishment_settings Everyone can view establishment settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Everyone can view establishment settings" ON public.establishment_settings FOR SELECT USING (true);


--
-- Name: training_courses Everyone views courses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Everyone views courses" ON public.training_courses FOR SELECT USING (true);


--
-- Name: jobs Everyone views open jobs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Everyone views open jobs" ON public.jobs FOR SELECT USING (true);


--
-- Name: recognitions Everyone views recognitions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Everyone views recognitions" ON public.recognitions FOR SELECT USING (true);


--
-- Name: surveys Everyone views surveys; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Everyone views surveys" ON public.surveys FOR SELECT USING (true);


--
-- Name: time_punches HR Managers can view all punches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "HR Managers can view all punches" ON public.time_punches FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles viewer
  WHERE ((viewer.id = auth.uid()) AND (COALESCE(viewer.is_active, true) = true) AND (upper(TRIM(BOTH FROM COALESCE(viewer.job_title, ''::character varying))) = 'HR MANAGER'::text)))));


--
-- Name: contract_documents HR and Admin can manage contract documents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "HR and Admin can manage contract documents" ON public.contract_documents TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles viewer
  WHERE ((viewer.id = auth.uid()) AND ((upper((COALESCE(viewer.role, ''::character varying))::text) = ANY (ARRAY['ADMIN'::text, 'ROLE_SYSTEM_ADMIN'::text, 'SYSTEM_ADMIN'::text])) OR (upper(TRIM(BOTH FROM COALESCE(viewer.job_title, ''::character varying))) = 'HR MANAGER'::text)))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles viewer
  WHERE ((viewer.id = auth.uid()) AND ((upper((COALESCE(viewer.role, ''::character varying))::text) = ANY (ARRAY['ADMIN'::text, 'ROLE_SYSTEM_ADMIN'::text, 'SYSTEM_ADMIN'::text])) OR (upper(TRIM(BOTH FROM COALESCE(viewer.job_title, ''::character varying))) = 'HR MANAGER'::text))))));


--
-- Name: job_titles Job Titles are deletable by admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Job Titles are deletable by admins" ON public.job_titles FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SUPER_ADMIN'::character varying, 'HR_MANAGER'::character varying])::text[]))))));


--
-- Name: job_titles Job Titles are insertable by admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Job Titles are insertable by admins" ON public.job_titles FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SUPER_ADMIN'::character varying, 'HR_MANAGER'::character varying])::text[]))))));


--
-- Name: job_titles Job Titles are updatable by admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Job Titles are updatable by admins" ON public.job_titles FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = ANY ((ARRAY['ADMIN'::character varying, 'SUPER_ADMIN'::character varying, 'HR_MANAGER'::character varying])::text[]))))));


--
-- Name: performance_goals Managers can delete team goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can delete team goals" ON public.performance_goals FOR DELETE USING ((auth.uid() IN ( SELECT profiles.manager_id
   FROM public.profiles
  WHERE (profiles.id = performance_goals.employee_id))));


--
-- Name: performance_goals Managers can insert team goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can insert team goals" ON public.performance_goals FOR INSERT WITH CHECK ((auth.uid() IN ( SELECT profiles.manager_id
   FROM public.profiles
  WHERE (profiles.id = performance_goals.employee_id))));


--
-- Name: performance_goals Managers can manage team goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can manage team goals" ON public.performance_goals USING ((employee_id IN ( SELECT profiles.id
   FROM public.profiles
  WHERE (profiles.manager_id = auth.uid()))));


--
-- Name: profiles Managers can read team profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can read team profiles" ON public.profiles FOR SELECT USING (((manager_id = auth.uid()) OR (id = auth.uid())));


--
-- Name: performance_goals Managers can update team goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can update team goals" ON public.performance_goals FOR UPDATE USING ((auth.uid() IN ( SELECT profiles.manager_id
   FROM public.profiles
  WHERE (profiles.id = performance_goals.employee_id))));


--
-- Name: performance_goals Managers can view team goals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers can view team goals" ON public.performance_goals FOR SELECT USING ((auth.uid() IN ( SELECT profiles.manager_id
   FROM public.profiles
  WHERE (profiles.id = performance_goals.employee_id))));


--
-- Name: contract_print_requests Managers decide contract print requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Managers decide contract print requests" ON public.contract_print_requests FOR UPDATE TO authenticated USING (((manager_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (upper((COALESCE(p.role, ''::character varying))::text) = 'ADMIN'::text)))))) WITH CHECK (((manager_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (upper((COALESCE(p.role, ''::character varying))::text) = 'ADMIN'::text))))));


--
-- Name: announcements Only admins can insert announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can insert announcements" ON public.announcements FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: crm_deal_attachments Owners and admins can delete deal attachments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Owners and admins can delete deal attachments" ON public.crm_deal_attachments FOR DELETE TO authenticated USING (((uploaded_by = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND ((p.role)::text = 'ADMIN'::text))))));


--
-- Name: performance_reviews Reviewers update their reviews; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Reviewers update their reviews" ON public.performance_reviews FOR UPDATE USING ((auth.uid() = reviewer_id));


--
-- Name: reminders Users can create their reminders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can create their reminders" ON public.reminders FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: crm_clients Users can delete clients; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete clients" ON public.crm_clients FOR DELETE USING (true);


--
-- Name: crm_orders Users can delete orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete orders" ON public.crm_orders FOR DELETE USING (true);


--
-- Name: reminders Users can delete their reminders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete their reminders" ON public.reminders FOR DELETE TO authenticated USING ((user_id = auth.uid()));


--
-- Name: crm_clients Users can insert clients; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert clients" ON public.crm_clients FOR INSERT WITH CHECK (true);


--
-- Name: messages Users can insert messages as sender; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert messages as sender" ON public.messages FOR INSERT WITH CHECK ((auth.uid() = sender_id));


--
-- Name: crm_orders Users can insert orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert orders" ON public.crm_orders FOR INSERT WITH CHECK (true);


--
-- Name: notifications Users can manage their own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can manage their own notifications" ON public.notifications USING ((auth.uid() = user_id));


--
-- Name: messages Users can read their own messages; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read their own messages" ON public.messages FOR SELECT USING (((auth.uid() = sender_id) OR (auth.uid() = receiver_id)));


--
-- Name: profiles Users can read their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read their own profile" ON public.profiles FOR SELECT USING ((auth.uid() = id));


--
-- Name: crm_clients Users can update clients; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update clients" ON public.crm_clients FOR UPDATE USING (true);


--
-- Name: crm_orders Users can update orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update orders" ON public.crm_orders FOR UPDATE USING (true);


--
-- Name: messages Users can update received messages; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update received messages" ON public.messages FOR UPDATE USING ((auth.uid() = receiver_id));


--
-- Name: profiles Users can update their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING ((auth.uid() = id));


--
-- Name: reminders Users can update their reminders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their reminders" ON public.reminders FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: crm_clients Users can view clients; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view clients" ON public.crm_clients FOR SELECT USING (true);


--
-- Name: crm_orders Users can view orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view orders" ON public.crm_orders FOR SELECT USING (true);


--
-- Name: payroll Users can view own payroll; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own payroll" ON public.payroll FOR SELECT USING ((auth.uid() = employee_id));


--
-- Name: released_payslips Users can view their own released payslips or admins can view a; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their own released payslips or admins can view a" ON public.released_payslips FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (((profiles.role)::text = 'ADMIN'::text) OR ((profiles.job_title)::text ~~* '%manager%'::text)))))));


--
-- Name: reminders Users can view their reminders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view their reminders" ON public.reminders FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: push_subscriptions Users manage their push subscriptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users manage their push subscriptions" ON public.push_subscriptions TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: performance_reviews Users view their own reviews; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users view their own reviews" ON public.performance_reviews FOR SELECT USING (((auth.uid() = employee_id) OR (auth.uid() = reviewer_id)));


--
-- Name: absences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.absences ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance admin_company_attendance_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_company_attendance_select ON public.attendance FOR SELECT TO authenticated USING (public.can_manage_attendance_records(auth.uid()));


--
-- Name: attendance admin_company_attendance_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_company_attendance_update ON public.attendance FOR UPDATE TO authenticated USING (public.can_manage_attendance_records(auth.uid())) WITH CHECK (public.can_manage_attendance_records(auth.uid()));


--
-- Name: admin_password_reset_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_password_reset_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: office_settings admins manage office settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admins manage office settings" ON public.office_settings TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'ADMIN'::text)))));


--
-- Name: profiles admins update profiles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "admins update profiles" ON public.profiles FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND ((p.role)::text = 'ADMIN'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND ((p.role)::text = 'ADMIN'::text)))));


--
-- Name: announcements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

--
-- Name: announcements announcements_admin_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY announcements_admin_insert ON public.announcements FOR INSERT TO authenticated WITH CHECK (((admin_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (upper((COALESCE(profiles.role, ''::character varying))::text) = ANY (ARRAY['ADMIN'::text, 'ROLE_SYSTEM_ADMIN'::text])))))));


--
-- Name: announcements announcements_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY announcements_authenticated_select ON public.announcements FOR SELECT TO authenticated USING (true);


--
-- Name: attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance attendance_own_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_own_insert ON public.attendance FOR INSERT TO authenticated WITH CHECK ((employee_id = auth.uid()));


--
-- Name: attendance attendance_own_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_own_update ON public.attendance FOR UPDATE TO authenticated USING ((employee_id = auth.uid())) WITH CHECK ((employee_id = auth.uid()));


--
-- Name: attendance attendance_scoped_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_scoped_select ON public.attendance FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.profiles profile
  WHERE ((profile.id = auth.uid()) AND (upper(btrim((COALESCE(profile.job_title, ''::character varying))::text)) = 'HR MANAGER'::text))))));


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: office_settings authenticated read office settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "authenticated read office settings" ON public.office_settings FOR SELECT TO authenticated USING (true);


--
-- Name: candidates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.candidates ENABLE ROW LEVEL SECURITY;

--
-- Name: commission_tiers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.commission_tiers ENABLE ROW LEVEL SECURITY;

--
-- Name: community_chat; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.community_chat ENABLE ROW LEVEL SECURITY;

--
-- Name: contract_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contract_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: contract_print_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contract_print_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: contract_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contract_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: contracts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_deal_activity crm_authorized_activity_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_activity_insert ON public.crm_deal_activity FOR INSERT TO authenticated WITH CHECK (public.can_access_crm(auth.uid()));


--
-- Name: crm_deal_activity crm_authorized_activity_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_activity_select ON public.crm_deal_activity FOR SELECT TO authenticated USING (public.can_access_crm(auth.uid()));


--
-- Name: crm_deal_approval_steps crm_authorized_approval_steps_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_approval_steps_select ON public.crm_deal_approval_steps FOR SELECT TO authenticated USING (public.can_access_crm(auth.uid()));


--
-- Name: crm_deal_attachments crm_authorized_attachments_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_attachments_delete ON public.crm_deal_attachments FOR DELETE TO authenticated USING (public.can_access_crm(auth.uid()));


--
-- Name: crm_deal_attachments crm_authorized_attachments_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_attachments_insert ON public.crm_deal_attachments FOR INSERT TO authenticated WITH CHECK (public.can_access_crm(auth.uid()));


--
-- Name: crm_deal_attachments crm_authorized_attachments_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_attachments_select ON public.crm_deal_attachments FOR SELECT TO authenticated USING ((public.can_access_crm(auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.tasks task
  WHERE ((task.crm_deal_id = crm_deal_attachments.deal_id) AND (task.crm_workflow_kind = 'QUOTE_PROPOSAL_DESIGN'::text) AND ((auth.uid() = task.assignee_id) OR (auth.uid() = task.created_by)))))));


--
-- Name: crm_clients crm_authorized_clients_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_clients_all ON public.crm_clients TO authenticated USING (public.can_access_crm(auth.uid())) WITH CHECK (public.can_access_crm(auth.uid()));


--
-- Name: crm_deals crm_authorized_deals_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_deals_insert ON public.crm_deals FOR INSERT TO authenticated WITH CHECK (public.can_access_crm(auth.uid()));


--
-- Name: crm_deals crm_authorized_deals_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_deals_select ON public.crm_deals FOR SELECT TO authenticated USING (public.can_access_crm(auth.uid()));


--
-- Name: crm_deals crm_authorized_deals_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_authorized_deals_update ON public.crm_deals FOR UPDATE TO authenticated USING (public.can_access_crm(auth.uid())) WITH CHECK (public.can_access_crm(auth.uid()));


--
-- Name: crm_clients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_clients ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_deal_activity; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_deal_activity ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_deal_approval_steps; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_deal_approval_steps ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_deal_attachments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_deal_attachments ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_deals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_design_task_approval_steps crm_design_task_approval_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_design_task_approval_select ON public.crm_design_task_approval_steps FOR SELECT TO authenticated USING (((approver_id = auth.uid()) OR public.can_access_crm(auth.uid()) OR (EXISTS ( SELECT 1
   FROM public.tasks task
  WHERE ((task.id = crm_design_task_approval_steps.task_id) AND ((auth.uid() = task.assignee_id) OR (auth.uid() = task.created_by)))))));


--
-- Name: crm_design_task_approval_steps; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_design_task_approval_steps ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_deals crm_privileged_deals_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_privileged_deals_delete ON public.crm_deals FOR DELETE TO authenticated USING (public.can_delete_crm_deal(auth.uid()));


--
-- Name: crm_deal_attachments crm_project_shared_attachments_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY crm_project_shared_attachments_select ON public.crm_deal_attachments FOR SELECT TO authenticated USING (((is_archived = false) AND (visible_to_project_assignee = true) AND (EXISTS ( SELECT 1
   FROM public.projects project
  WHERE ((project.deal_id = crm_deal_attachments.deal_id) AND (auth.uid() = ANY (COALESCE(project.assigned_people, ARRAY[]::uuid[]))))))));


--
-- Name: departments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

--
-- Name: document_expiry_notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.document_expiry_notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: document_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.document_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: document_requests document_requests_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_requests_admin_delete ON public.document_requests FOR DELETE TO authenticated USING (public.is_system_admin(auth.uid()));


--
-- Name: document_requests document_requests_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_requests_admin_update ON public.document_requests FOR UPDATE TO authenticated USING (public.is_system_admin(auth.uid())) WITH CHECK (public.is_system_admin(auth.uid()));


--
-- Name: document_requests document_requests_scoped_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_requests_scoped_insert ON public.document_requests FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(), employee_id)));


--
-- Name: document_requests document_requests_scoped_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_requests_scoped_select ON public.document_requests FOR SELECT TO authenticated USING (public.can_view_employee_request('document_requests'::text, id, employee_id, auth.uid()));


--
-- Name: employee_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_documents employee_documents_own_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_documents_own_insert ON public.employee_documents FOR INSERT TO authenticated WITH CHECK ((employee_id = auth.uid()));


--
-- Name: employee_documents employee_documents_scoped_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_documents_scoped_delete ON public.employee_documents FOR DELETE TO authenticated USING (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(), employee_id)));


--
-- Name: employee_documents employee_documents_scoped_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_documents_scoped_select ON public.employee_documents FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(), employee_id)));


--
-- Name: employee_documents employee_documents_scoped_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_documents_scoped_update ON public.employee_documents FOR UPDATE TO authenticated USING (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(), employee_id))) WITH CHECK (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(), employee_id)));


--
-- Name: employee_loans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_loans ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_training; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_training ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance employees_radar_company_attendance_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employees_radar_company_attendance_select ON public.attendance FOR SELECT TO authenticated USING ((public.can_view_employees_radar(auth.uid()) AND (date = ((now() AT TIME ZONE 'Asia/Riyadh'::text))::date)));


--
-- Name: establishment_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.establishment_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance executive_admin_full_attendance_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY executive_admin_full_attendance_select ON public.attendance FOR SELECT TO authenticated USING (public.can_view_all_attendance(auth.uid()));


--
-- Name: profiles executive_company_employee_names_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY executive_company_employee_names_select ON public.profiles FOR SELECT TO authenticated USING (public.can_view_company_employee_names(auth.uid()));


--
-- Name: task_lists executive_company_task_lists_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY executive_company_task_lists_select ON public.task_lists FOR SELECT TO authenticated USING (public.can_assign_tasks_company_wide(auth.uid()));


--
-- Name: tasks executive_company_tasks_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY executive_company_tasks_insert ON public.tasks FOR INSERT TO authenticated WITH CHECK (((created_by = auth.uid()) AND public.can_assign_tasks_company_wide(auth.uid())));


--
-- Name: tasks executive_company_tasks_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY executive_company_tasks_select ON public.tasks FOR SELECT TO authenticated USING (public.can_assign_tasks_company_wide(auth.uid()));


--
-- Name: tasks executive_company_tasks_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY executive_company_tasks_update ON public.tasks FOR UPDATE TO authenticated USING (public.can_assign_tasks_company_wide(auth.uid())) WITH CHECK (public.can_assign_tasks_company_wide(auth.uid()));


--
-- Name: expense_claims; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expense_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: expenses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

--
-- Name: expenses expenses_own_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expenses_own_delete ON public.expenses FOR DELETE TO authenticated USING (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid())));


--
-- Name: expenses expenses_own_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expenses_own_update ON public.expenses FOR UPDATE TO authenticated USING (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()))) WITH CHECK (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid())));


--
-- Name: expenses expenses_scoped_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expenses_scoped_insert ON public.expenses FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(), employee_id)));


--
-- Name: expenses expenses_scoped_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY expenses_scoped_select ON public.expenses FOR SELECT TO authenticated USING (public.can_view_employee_request('expenses'::text, id, employee_id, auth.uid()));


--
-- Name: goals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.goals ENABLE ROW LEVEL SECURITY;

--
-- Name: hr_suite_beta_items hr_suite_beta_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_suite_beta_insert ON public.hr_suite_beta_items FOR INSERT TO authenticated WITH CHECK (public.can_manage_hr_suite_beta(auth.uid()));


--
-- Name: hr_suite_beta_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.hr_suite_beta_items ENABLE ROW LEVEL SECURITY;

--
-- Name: hr_suite_beta_items hr_suite_beta_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_suite_beta_select ON public.hr_suite_beta_items FOR SELECT TO authenticated USING (public.can_manage_hr_suite_beta(auth.uid()));


--
-- Name: hr_suite_beta_items hr_suite_beta_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY hr_suite_beta_update ON public.hr_suite_beta_items FOR UPDATE TO authenticated USING (public.can_manage_hr_suite_beta(auth.uid())) WITH CHECK (public.can_manage_hr_suite_beta(auth.uid()));


--
-- Name: job_titles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_titles ENABLE ROW LEVEL SECURITY;

--
-- Name: job_titles job_titles_authenticated_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY job_titles_authenticated_select ON public.job_titles FOR SELECT TO authenticated USING ((is_active = true));


--
-- Name: jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_requests leave_requests_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_requests_admin_delete ON public.leave_requests FOR DELETE TO authenticated USING (public.is_system_admin(auth.uid()));


--
-- Name: leave_requests leave_requests_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_requests_admin_update ON public.leave_requests FOR UPDATE TO authenticated USING (public.is_system_admin(auth.uid())) WITH CHECK (public.is_system_admin(auth.uid()));


--
-- Name: leave_requests leave_requests_scoped_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_requests_scoped_insert ON public.leave_requests FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(), employee_id)));


--
-- Name: leave_requests leave_requests_scoped_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_requests_scoped_select ON public.leave_requests FOR SELECT TO authenticated USING (public.can_view_employee_request('leave_requests'::text, id, employee_id, auth.uid()));


--
-- Name: login_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: task_lists marketing_and_granted_task_lists_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY marketing_and_granted_task_lists_select ON public.task_lists FOR SELECT TO authenticated USING (((public.is_marketing_task_manager(auth.uid()) AND public.is_marketing_managed_task_list(id)) OR public.can_view_task_list_via_employee_grant(id, auth.uid())));


--
-- Name: tasks marketing_and_granted_tasks_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY marketing_and_granted_tasks_select ON public.tasks FOR SELECT TO authenticated USING ((public.can_view_task_via_employee_grant(id, auth.uid()) OR public.can_marketing_manager_edit_task(id, auth.uid())));


--
-- Name: task_comments marketing_manager_task_comments_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY marketing_manager_task_comments_delete ON public.task_comments FOR DELETE TO authenticated USING (public.can_marketing_manager_edit_task(task_id, auth.uid()));


--
-- Name: task_comments marketing_manager_task_comments_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY marketing_manager_task_comments_insert ON public.task_comments FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.can_marketing_manager_edit_task(task_id, auth.uid())));


--
-- Name: task_comments marketing_manager_task_comments_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY marketing_manager_task_comments_update ON public.task_comments FOR UPDATE TO authenticated USING (public.can_marketing_manager_edit_task(task_id, auth.uid())) WITH CHECK (public.can_marketing_manager_edit_task(task_id, auth.uid()));


--
-- Name: tasks marketing_manager_tasks_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY marketing_manager_tasks_update ON public.tasks FOR UPDATE TO authenticated USING (public.can_marketing_manager_edit_task(id, auth.uid())) WITH CHECK ((public.is_marketing_task_manager(auth.uid()) AND public.is_marketing_managed_task_list(task_list_id)));


--
-- Name: messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: monthly_sales; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.monthly_sales ENABLE ROW LEVEL SECURITY;

--
-- Name: task_lists mq07_design_list_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq07_design_list_select ON public.task_lists FOR SELECT TO authenticated USING (public.is_mq07_design_list(id, auth.uid()));


--
-- Name: tasks mq07_design_tasks_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq07_design_tasks_insert ON public.tasks FOR INSERT TO authenticated WITH CHECK (((created_by = auth.uid()) AND public.is_mq07_design_list(task_list_id, auth.uid())));


--
-- Name: tasks mq07_design_tasks_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq07_design_tasks_select ON public.tasks FOR SELECT TO authenticated USING (public.is_mq07_design_list(task_list_id, auth.uid()));


--
-- Name: tasks mq07_design_tasks_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq07_design_tasks_update_own ON public.tasks FOR UPDATE TO authenticated USING (((created_by = auth.uid()) AND public.is_mq07_design_list(task_list_id, auth.uid()))) WITH CHECK (((created_by = auth.uid()) AND public.is_mq07_design_list(task_list_id, auth.uid())));


--
-- Name: task_comments mq20_no_task_comments_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_task_comments_delete ON public.task_comments AS RESTRICTIVE FOR DELETE TO authenticated USING ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: task_comments mq20_no_task_comments_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_task_comments_insert ON public.task_comments AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: task_comments mq20_no_task_comments_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_task_comments_update ON public.task_comments AS RESTRICTIVE FOR UPDATE TO authenticated USING ((NOT public.is_mq20_profile(auth.uid()))) WITH CHECK ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: task_lists mq20_no_task_lists_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_task_lists_delete ON public.task_lists AS RESTRICTIVE FOR DELETE TO authenticated USING ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: task_lists mq20_no_task_lists_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_task_lists_insert ON public.task_lists AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: task_lists mq20_no_task_lists_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_task_lists_update ON public.task_lists AS RESTRICTIVE FOR UPDATE TO authenticated USING ((NOT public.is_mq20_profile(auth.uid()))) WITH CHECK ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: tasks mq20_no_tasks_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_tasks_delete ON public.tasks AS RESTRICTIVE FOR DELETE TO authenticated USING ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: tasks mq20_no_tasks_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_tasks_insert ON public.tasks AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: tasks mq20_no_tasks_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_no_tasks_update ON public.tasks AS RESTRICTIVE FOR UPDATE TO authenticated USING ((NOT public.is_mq20_profile(auth.uid()))) WITH CHECK ((NOT public.is_mq20_profile(auth.uid())));


--
-- Name: task_comments mq20_only_ines_task_comments_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_only_ines_task_comments_select ON public.task_comments AS RESTRICTIVE FOR SELECT TO authenticated USING (((NOT public.is_mq20_profile(auth.uid())) OR public.is_ines_modani_task(task_id)));


--
-- Name: task_lists mq20_only_ines_task_lists_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_only_ines_task_lists_select ON public.task_lists AS RESTRICTIVE FOR SELECT TO authenticated USING (((NOT public.is_mq20_profile(auth.uid())) OR public.is_ines_modani_task_list(id)));


--
-- Name: tasks mq20_only_ines_tasks_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY mq20_only_ines_tasks_select ON public.tasks AS RESTRICTIVE FOR SELECT TO authenticated USING (((NOT public.is_mq20_profile(auth.uid())) OR public.is_ines_modani_task(id)));


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: office_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.office_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_adjustments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_adjustments ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: performance_goals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.performance_goals ENABLE ROW LEVEL SECURITY;

--
-- Name: performance_reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.performance_reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: projects project_portfolio_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY project_portfolio_delete ON public.projects FOR DELETE TO authenticated USING (((created_by = auth.uid()) OR (project_manager_id = auth.uid()) OR public.is_project_portfolio_admin(auth.uid())));


--
-- Name: projects project_portfolio_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY project_portfolio_insert ON public.projects FOR INSERT TO authenticated WITH CHECK (((created_by = auth.uid()) AND ((project_manager_id = auth.uid()) OR public.is_project_portfolio_admin(auth.uid()))));


--
-- Name: projects project_portfolio_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY project_portfolio_select ON public.projects FOR SELECT TO authenticated USING (((created_by = auth.uid()) OR (project_manager_id = auth.uid()) OR (auth.uid() = ANY (COALESCE(assigned_people, ARRAY[]::uuid[]))) OR public.is_project_portfolio_admin(auth.uid())));


--
-- Name: projects project_portfolio_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY project_portfolio_update ON public.projects FOR UPDATE TO authenticated USING (((created_by = auth.uid()) OR (project_manager_id = auth.uid()) OR public.is_project_portfolio_admin(auth.uid()))) WITH CHECK (((created_by = auth.uid()) OR (project_manager_id = auth.uid()) OR public.is_project_portfolio_admin(auth.uid())));


--
-- Name: project_todos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.project_todos ENABLE ROW LEVEL SECURITY;

--
-- Name: project_todos project_todos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY project_todos_select ON public.project_todos FOR SELECT TO authenticated USING (public.can_access_project(project_id, auth.uid()));


--
-- Name: project_updates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.project_updates ENABLE ROW LEVEL SECURITY;

--
-- Name: project_updates project_updates_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY project_updates_insert ON public.project_updates FOR INSERT TO authenticated WITH CHECK (((author_id = auth.uid()) AND public.can_access_project(project_id, auth.uid())));


--
-- Name: project_updates project_updates_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY project_updates_select ON public.project_updates FOR SELECT TO authenticated USING (public.can_access_project(project_id, auth.uid()));


--
-- Name: projects; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

--
-- Name: push_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: recognitions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recognitions ENABLE ROW LEVEL SECURITY;

--
-- Name: released_payslips; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.released_payslips ENABLE ROW LEVEL SECURITY;

--
-- Name: reminders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reminders ENABLE ROW LEVEL SECURITY;

--
-- Name: request_approval_steps; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.request_approval_steps ENABLE ROW LEVEL SECURITY;

--
-- Name: request_approval_workflows; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.request_approval_workflows ENABLE ROW LEVEL SECURITY;

--
-- Name: request_approval_steps request_steps_visible; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY request_steps_visible ON public.request_approval_steps FOR SELECT TO authenticated USING (public.can_view_request_workflow(workflow_id, auth.uid()));


--
-- Name: request_approval_workflows request_workflows_visible; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY request_workflows_visible ON public.request_approval_workflows FOR SELECT TO authenticated USING (public.can_view_request_workflow(id, auth.uid()));


--
-- Name: requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.requests ENABLE ROW LEVEL SECURITY;

--
-- Name: requests requests_admin_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY requests_admin_delete ON public.requests FOR DELETE TO authenticated USING (public.is_system_admin(auth.uid()));


--
-- Name: requests requests_admin_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY requests_admin_update ON public.requests FOR UPDATE TO authenticated USING (public.is_system_admin(auth.uid())) WITH CHECK (public.is_system_admin(auth.uid()));


--
-- Name: requests requests_scoped_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY requests_scoped_insert ON public.requests FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) OR public.is_system_admin(auth.uid()) OR public.is_department_manager_for(auth.uid(), employee_id)));


--
-- Name: requests requests_scoped_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY requests_scoped_select ON public.requests FOR SELECT TO authenticated USING (public.can_view_employee_request('requests'::text, id, employee_id, auth.uid()));


--
-- Name: role_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: shifts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;

--
-- Name: survey_responses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.survey_responses ENABLE ROW LEVEL SECURITY;

--
-- Name: surveys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.surveys ENABLE ROW LEVEL SECURITY;

--
-- Name: system_translations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.system_translations ENABLE ROW LEVEL SECURITY;

--
-- Name: task_activity; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_activity ENABLE ROW LEVEL SECURITY;

--
-- Name: task_activity task_activity_secure_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_activity_secure_select ON public.task_activity FOR SELECT TO authenticated USING (public.can_access_task(task_id, auth.uid()));


--
-- Name: task_attachments task_attachment_versioned_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_attachment_versioned_select ON public.task_attachments FOR SELECT TO authenticated USING ((public.can_manage_task_attachments(task_id, auth.uid()) OR ((is_archived = false) AND (visible_to_project_assignee = true) AND (EXISTS ( SELECT 1
   FROM (public.tasks task
     JOIN public.projects project ON (((project.id = task.project_id) OR ((project.deal_id IS NOT NULL) AND (project.deal_id = task.crm_deal_id)))))
  WHERE ((task.id = task_attachments.task_id) AND (auth.uid() = ANY (COALESCE(project.assigned_people, ARRAY[]::uuid[])))))))));


--
-- Name: task_attachments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_attachments ENABLE ROW LEVEL SECURITY;

--
-- Name: task_attachments task_attachments_delete_secure; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_attachments_delete_secure ON public.task_attachments FOR DELETE TO authenticated USING (public.can_manage_task_attachments(task_id, auth.uid()));


--
-- Name: task_attachments task_attachments_insert_secure; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_attachments_insert_secure ON public.task_attachments FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.can_manage_task_attachments(task_id, auth.uid())));


--
-- Name: task_attachments task_attachments_update_secure; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_attachments_update_secure ON public.task_attachments FOR UPDATE TO authenticated USING (public.can_manage_task_attachments(task_id, auth.uid())) WITH CHECK (public.can_manage_task_attachments(task_id, auth.uid()));


--
-- Name: task_comments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;

--
-- Name: task_comments task_comments_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_comments_delete_own ON public.task_comments FOR DELETE TO authenticated USING (((user_id = auth.uid()) OR public.is_task_admin(auth.uid())));


--
-- Name: task_comments task_comments_insert_authorized; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_comments_insert_authorized ON public.task_comments FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.can_view_task(task_id, auth.uid())));


--
-- Name: task_comments task_comments_secure_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_comments_secure_delete ON public.task_comments FOR DELETE TO authenticated USING (((user_id = auth.uid()) OR public.can_manage_task(task_id, auth.uid())));


--
-- Name: task_comments task_comments_secure_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_comments_secure_insert ON public.task_comments FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND public.can_access_task(task_id, auth.uid())));


--
-- Name: task_comments task_comments_secure_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_comments_secure_select ON public.task_comments FOR SELECT TO authenticated USING (public.can_access_task(task_id, auth.uid()));


--
-- Name: task_comments task_comments_secure_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_comments_secure_update ON public.task_comments FOR UPDATE TO authenticated USING (((user_id = auth.uid()) OR public.can_manage_task(task_id, auth.uid()))) WITH CHECK (((user_id = auth.uid()) OR public.can_manage_task(task_id, auth.uid())));


--
-- Name: task_comments task_comments_select_authorized; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_comments_select_authorized ON public.task_comments FOR SELECT TO authenticated USING (public.can_view_task(task_id, auth.uid()));


--
-- Name: task_comments task_comments_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_comments_update_own ON public.task_comments FOR UPDATE TO authenticated USING (((user_id = auth.uid()) OR public.is_task_admin(auth.uid()))) WITH CHECK (((user_id = auth.uid()) OR public.is_task_admin(auth.uid())));


--
-- Name: task_email_outbox; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_email_outbox ENABLE ROW LEVEL SECURITY;

--
-- Name: task_employee_access_grants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_employee_access_grants ENABLE ROW LEVEL SECURITY;

--
-- Name: task_employee_access_grants task_employee_access_visible; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_employee_access_visible ON public.task_employee_access_grants FOR SELECT TO authenticated USING (((viewer_id = auth.uid()) OR public.is_marketing_task_manager(auth.uid())));


--
-- Name: task_lists; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.task_lists ENABLE ROW LEVEL SECURITY;

--
-- Name: task_lists task_lists_delete_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_lists_delete_owner ON public.task_lists FOR DELETE TO authenticated USING ((owner_id = auth.uid()));


--
-- Name: task_lists task_lists_insert_authenticated_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_lists_insert_authenticated_owner ON public.task_lists FOR INSERT TO authenticated WITH CHECK ((owner_id = auth.uid()));


--
-- Name: task_lists task_lists_select_department; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_lists_select_department ON public.task_lists FOR SELECT TO authenticated USING (public.can_view_task_list(id, auth.uid()));


--
-- Name: task_lists task_lists_update_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_lists_update_owner ON public.task_lists FOR UPDATE TO authenticated USING ((owner_id = auth.uid())) WITH CHECK ((owner_id = auth.uid()));


--
-- Name: tasks task_secure_access_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY task_secure_access_select ON public.tasks AS RESTRICTIVE FOR SELECT TO authenticated USING (public.can_access_task(id, auth.uid()));


--
-- Name: tasks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

--
-- Name: tasks tasks_delete_authorized; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tasks_delete_authorized ON public.tasks FOR DELETE TO authenticated USING (public.can_delete_task(id, auth.uid()));


--
-- Name: tasks tasks_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tasks_insert_own ON public.tasks FOR INSERT TO authenticated WITH CHECK (((created_by = auth.uid()) AND ((task_list_id IS NULL) OR public.can_add_task_to_list(task_list_id, auth.uid()))));


--
-- Name: tasks tasks_select_authorized; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tasks_select_authorized ON public.tasks FOR SELECT TO authenticated USING (public.can_view_task(id, auth.uid()));


--
-- Name: tasks tasks_select_own_created; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tasks_select_own_created ON public.tasks FOR SELECT TO authenticated USING ((created_by = auth.uid()));


--
-- Name: tasks tasks_update_authorized; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tasks_update_authorized ON public.tasks FOR UPDATE TO authenticated USING (public.can_manage_task(id, auth.uid())) WITH CHECK (public.can_manage_task(id, auth.uid()));


--
-- Name: time_punches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.time_punches ENABLE ROW LEVEL SECURITY;

--
-- Name: training_courses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.training_courses ENABLE ROW LEVEL SECURITY;

--
-- Name: user_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: webhooks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.webhooks ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict 7GtYyiaEQtO4ufGqWWb2lCra7cpDqp7zjJx2XCier5JGbWqoXC71XzIl9qSwzEz

