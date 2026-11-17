\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(id) SELECT ('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid FROM generate_series(1,6) n;
INSERT INTO public.departments(id,name) VALUES ('b2000000-0000-4000-8000-000000000001','Synthetic department A'),('b2000000-0000-4000-8000-000000000002','Synthetic department B');
INSERT INTO public.profiles(id,full_name,role,is_active,department_id,task_email_notifications)
SELECT ('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Synthetic test',CASE n WHEN 3 THEN 'MANAGER' WHEN 4 THEN 'SUPERVISOR' ELSE 'EMPLOYEE' END, n<>6,
CASE WHEN n=5 THEN 'b2000000-0000-4000-8000-000000000002'::uuid ELSE 'b2000000-0000-4000-8000-000000000001'::uuid END,false FROM generate_series(1,6) n;
INSERT INTO public.tasks(id,title,created_by,assignee_id,assignee_ids,visibility,status,archived_at)
VALUES ('b3000000-0000-4000-8000-000000000001','Synthetic archived','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002',ARRAY['b1000000-0000-4000-8000-000000000002'::uuid],'private','todo',now()),
('b3000000-0000-4000-8000-000000000002','Synthetic active','b1000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000002',ARRAY['b1000000-0000-4000-8000-000000000002'::uuid],'private','todo',NULL);
SET LOCAL ROLE authenticated;
DO $$ DECLARE n int; allowed boolean; visible boolean; BEGIN
 FOR n IN 1..6 LOOP
   PERFORM set_config('request.jwt.claim.sub',('b1000000-0000-4000-8000-'||lpad(n::text,12,'0')),true);
   SELECT public.can_view_archived_task('b3000000-0000-4000-8000-000000000001') INTO allowed;
   IF allowed IS DISTINCT FROM (n IN (1,2,3,4)) THEN RAISE EXCEPTION 'Archived helper mismatch for synthetic role %',n; END IF;
   IF public.can_view_archived_task('b3000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Active task accepted by archived helper'; END IF;
   SELECT EXISTS(SELECT 1 FROM public.tasks WHERE id='b3000000-0000-4000-8000-000000000001') INTO visible;
   IF visible IS DISTINCT FROM (n IN (1,2,3,4)) THEN RAISE EXCEPTION 'Archived task RLS mismatch for synthetic role %',n; END IF;
 END LOOP;
END $$;
ROLLBACK;
