\set ON_ERROR_STOP on
GRANT USAGE ON SCHEMA auth TO authenticated;
INSERT INTO auth.users(id) VALUES ('a1000000-0000-4000-8000-000000000001'),('a1000000-0000-4000-8000-000000000002');
INSERT INTO public.departments(id,name) VALUES ('a2000000-0000-4000-8000-000000000001','Synthetic Task Team');
INSERT INTO public.profiles(id,full_name,department_id,role,is_active,task_email_notifications) VALUES
 ('a1000000-0000-4000-8000-000000000001','Synthetic task creator','a2000000-0000-4000-8000-000000000001','EMPLOYEE',true,false),
 ('a1000000-0000-4000-8000-000000000002','Synthetic task assignee','a2000000-0000-4000-8000-000000000001','EMPLOYEE',true,false);
UPDATE public.departments SET head_id='a1000000-0000-4000-8000-000000000001' WHERE id='a2000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',false);
DO $$ DECLARE v jsonb; BEGIN
 v:=public.create_task_secure(jsonb_build_object('title','Synthetic task manager','assignee_id','a1000000-0000-4000-8000-000000000001','department','Synthetic Task Team','visibility','private'));
 PERFORM set_config('test.tm_task',v->>'id',false);
 IF NOT EXISTS(SELECT 1 FROM public.list_accessible_tasks_secure() x WHERE x->>'id'=v->>'id') THEN RAISE EXCEPTION 'Task list missing created task'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.tasks WHERE id=(v->>'id')::uuid) THEN RAISE EXCEPTION 'Task detail inaccessible'; END IF;
END $$;
SELECT public.add_task_comment(current_setting('test.tm_task')::uuid,'Synthetic comment','[]'::jsonb);
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.list_task_comments_secure(current_setting('test.tm_task')::uuid) WHERE content='Synthetic comment') THEN RAISE EXCEPTION 'Comment missing'; END IF; END $$;
SELECT public.assign_task(current_setting('test.tm_task')::uuid,ARRAY['a1000000-0000-4000-8000-000000000002'::uuid]);
SELECT set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',false);
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.list_accessible_tasks_secure() x WHERE x->>'id'=current_setting('test.tm_task')) THEN RAISE EXCEPTION 'Reassigned user cannot list task'; END IF; END $$;
RESET ROLE;
SELECT 'TASK_MANAGER_AUTHENTICATED=PASS';
