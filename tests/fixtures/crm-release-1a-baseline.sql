-- Synthetic schema only. This is a focused workflow fixture, not a complete
-- Supabase migration replay or an export of any connected database.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
GRANT USAGE ON SCHEMA auth, public TO authenticated, anon;
CREATE TABLE departments(id uuid PRIMARY KEY, name text, name_ar text, head_id uuid);
CREATE TABLE profiles(id uuid PRIMARY KEY, department_id uuid, role text, job_title text, manager_id uuid,
 full_name text, display_name text, display_name_ar text, job_title_ar text, employee_id text,
 task_email_notifications boolean DEFAULT false, is_active boolean DEFAULT true, emp_index integer);
CREATE TABLE crm_clients(id uuid PRIMARY KEY, name text, company text);
CREATE TABLE task_lists(id uuid PRIMARY KEY, name text, department_id uuid, owner_id uuid,
 can_add_users uuid[] DEFAULT '{}', can_delete_users uuid[] DEFAULT '{}', shared_with uuid[] DEFAULT '{}', created_at timestamptz DEFAULT now());
CREATE TABLE crm_deals(id uuid PRIMARY KEY, client_id uuid, title text, amount numeric DEFAULT 0,
 stage text DEFAULT 'LEAD', workflow_status text DEFAULT 'NOT_STARTED', approval_type text,
 created_by uuid, assigned_to uuid, technical_description text, design_task_id uuid,
 design_task_status text, design_task_due_date date, proposal_sent_at timestamptz, lost_reason text);
ALTER TABLE crm_deals ADD CONSTRAINT crm_deals_workflow_status_check CHECK (workflow_status IN ('NOT_STARTED','PENDING_APPROVAL','APPROVED','REJECTED','DESIGN_IN_PROGRESS','DESIGN_PENDING_APPROVAL','DESIGN_REJECTED'));
CREATE TABLE crm_deal_attachments(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), deal_id uuid,
 category text, file_url text, file_type text, description text, is_archived boolean DEFAULT false);
CREATE TABLE crm_deal_activity(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), deal_id uuid,
 action text, from_status text, to_status text, note text, actor_id uuid, created_at timestamptz DEFAULT now());
CREATE TABLE crm_deal_approval_steps(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), deal_id uuid, status text);
CREATE TABLE crm_design_task_approval_steps(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), deal_id uuid, status text);
CREATE TABLE tasks(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title varchar(255) NOT NULL, description text,
 assignee_id uuid, assignee_ids uuid[] DEFAULT '{}', created_by uuid, supervisor_id uuid,
 department text, task_list_id uuid REFERENCES task_lists, visibility text, visible_to uuid[] DEFAULT '{}',
 watchers uuid[] DEFAULT '{}', due_date date, start_date date, end_date date, estimated_time integer,
 status text DEFAULT 'todo', priority text, category text, sub_type text, content_type text,
 crm_deal_id uuid REFERENCES crm_deals ON DELETE SET NULL, crm_workflow_kind text,
 created_at timestamptz NOT NULL DEFAULT now(), completion_requested_by uuid, completion_requested_at timestamptz,
 completion_approved_by uuid, completion_approved_at timestamptz, submission_links text[] DEFAULT '{}',
 title_i18n jsonb, description_i18n jsonb, project_id uuid, tags text[], source_link text, upload_link text,
 parent_task_id uuid, marketing_department text, content_links text[], delivery_status text,
 repeat_type text, repeat_interval integer, notify_via_email boolean, attachments text[] DEFAULT '{}',
 work_state text DEFAULT 'ACTIVE', archived_at timestamptz, started_at timestamptz, completed_at timestamptz,
 waiting_category text, blocked_category text);
CREATE TABLE task_attachments(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), task_id uuid, file_url text,
 file_type text, is_archived boolean DEFAULT false);
CREATE TABLE notifications(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid, message text, event_type text,
 task_id uuid, actor_id uuid, action_url text, metadata jsonb, created_at timestamptz DEFAULT now());
CREATE TABLE auth.users(id uuid PRIMARY KEY, email text);
CREATE TABLE task_comments(id uuid PRIMARY KEY, task_id uuid, user_id uuid, content text, attachments jsonb, created_at timestamptz);
CREATE TABLE task_email_outbox(notification_id uuid, task_id uuid, recipient_id uuid, recipient_email text,
 subject text, message text, action_url text, comment_text text, attachment_links jsonb, always_send boolean, context_type text, details jsonb);
CREATE FUNCTION email_profile_name(uuid) RETURNS text LANGUAGE sql AS $$ SELECT $1::text $$;
CREATE TABLE task_activity(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), task_id uuid, actor_id uuid,
 action text, from_status text, to_status text, metadata jsonb);
CREATE TABLE projects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), deal_id uuid, created_at timestamptz DEFAULT now(),
 project_name text, project_type text, description text, assigned_people uuid[], project_tags text[], client_id uuid,
 event_date date, start_date date, end_date date, event_location text, project_amount numeric, paid_amount numeric,
 project_status text, source text, order_employee_id uuid, event_start_time time, installation_time timestamp,
 uninstallation_time timestamp, client_snapshot jsonb, event_location_text text, installation_type text, equipment jsonb);
-- Specialist permission helpers are conservative fixture substitutes. The test
-- runner loads real CRM, list and task façade predicates from repository SQL.
CREATE FUNCTION can_marketing_manager_edit_task(uuid, uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE FUNCTION can_view_task_via_employee_grant(uuid, uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE FUNCTION can_view_task_list_via_employee_grant(uuid, uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE FUNCTION can_access_project(uuid, uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE FUNCTION is_task_department_manager(text, uuid) RETURNS boolean LANGUAGE sql AS $$
 SELECT EXISTS(SELECT 1 FROM departments WHERE name = $1 AND head_id = $2) $$;
CREATE FUNCTION is_crm_approval_admin(uuid) RETURNS boolean LANGUAGE sql AS $$
 SELECT EXISTS(SELECT 1 FROM profiles WHERE id = $1 AND role = 'ADMIN') $$;
-- Retired functions must exist so the migration can revoke their privileges.
CREATE FUNCTION start_deal_approval(uuid, uuid, uuid, uuid) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION decide_deal_approval(uuid, text, text) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION decide_crm_design_task_approval(uuid, text, text) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION finalize_crm_deal_approval(uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION create_crm_design_task_for_deal(uuid) RETURNS uuid LANGUAGE sql AS $$ SELECT NULL::uuid $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
-- IDs: 1 Sales actor; 2 other Sales actor; 3 MQ-08; 4 outsider; 5 admin; 6 inactive Sales.
INSERT INTO departments(id,name,head_id) VALUES
 ('10000000-0000-0000-0000-000000000001','Sales','00000000-0000-0000-0000-000000000005'),
 ('10000000-0000-0000-0000-000000000002','Design',NULL),
 ('10000000-0000-0000-0000-000000000003','Other',NULL),
 ('10000000-0000-0000-0000-000000000004','Marketing',NULL);
INSERT INTO profiles(id, department_id, role, emp_index, is_active) VALUES
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','EMPLOYEE',1,true),
 ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','EMPLOYEE',2,true),
 ('00000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','EMPLOYEE',8,true),
 ('00000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000003','EMPLOYEE',4,true),
 ('00000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','ADMIN',5,true),
 ('00000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001','EMPLOYEE',6,false),
 ('00000000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001','EMPLOYEE',20,true);
UPDATE profiles SET employee_id='MQ-20', job_title='Sales Representative'
 WHERE id='00000000-0000-0000-0000-000000000007';
UPDATE profiles SET employee_id='MQ-08' WHERE id='00000000-0000-0000-0000-000000000003';
INSERT INTO crm_clients VALUES ('20000000-0000-0000-0000-000000000001','Example Client','Example Company');
INSERT INTO task_lists(id,name,department_id,owner_id) VALUES
 ('30000000-0000-0000-0000-000000000001','Design','10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
INSERT INTO crm_deals(id,client_id,title,created_by,assigned_to)
 SELECT ('40000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
 '20000000-0000-0000-0000-000000000001','Example Project',
 '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002'
 FROM generate_series(1,10) n;
INSERT INTO crm_deal_approval_steps(deal_id,status) VALUES ('40000000-0000-0000-0000-000000000001','PENDING');
INSERT INTO crm_design_task_approval_steps(deal_id,status) VALUES ('40000000-0000-0000-0000-000000000001','REJECTED');
UPDATE crm_deals SET stage='NEGOTIATION' WHERE id='40000000-0000-0000-0000-000000000006';
INSERT INTO tasks(id,title,assignee_id,created_by,status,crm_deal_id,crm_workflow_kind,submission_links,task_list_id)
 VALUES ('50000000-0000-0000-0000-000000000001','Historical Design','00000000-0000-0000-0000-000000000003',
 '00000000-0000-0000-0000-000000000001','Pending Approval','40000000-0000-0000-0000-000000000006',
 'QUOTE_PROPOSAL_DESIGN',ARRAY['storage://task-attachments/historical.pdf'],'30000000-0000-0000-0000-000000000001');
INSERT INTO task_attachments(task_id,file_url,file_type) VALUES
 ('50000000-0000-0000-0000-000000000001','storage://task-attachments/historical.pdf','application/pdf');
UPDATE crm_deals SET design_task_id='50000000-0000-0000-0000-000000000001' WHERE id='40000000-0000-0000-0000-000000000006';

-- Production baseline compatibility: the legacy trigger exists before the
-- Release 1A migration. It previously enforced approval gates, which the
-- Release 1A function intentionally retires while retaining data validation.
CREATE OR REPLACE FUNCTION public.enforce_deal_workflow_transition()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.stage IN ('PROPOSAL', 'NEGOTIATION', 'WON')
     AND COALESCE(NEW.workflow_status, 'NOT_STARTED') <> 'APPROVED' THEN
    RAISE EXCEPTION 'Legacy approval gate';
  END IF;
  IF NEW.stage = 'LOST' AND NULLIF(trim(COALESCE(NEW.lost_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A lost reason is required';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER crm_deals_enforce_workflow_transition
BEFORE INSERT OR UPDATE OF stage, workflow_status, lost_reason ON public.crm_deals
FOR EACH ROW EXECUTE FUNCTION public.enforce_deal_workflow_transition();
