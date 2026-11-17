-- Synthetic-only pre-final-migration fixture. Never execute on hosted databases.
INSERT INTO auth.users(id) VALUES ('e2000000-0000-4000-8000-000000000001');
INSERT INTO public.departments(id,name) VALUES ('e3000000-0000-4000-8000-000000000001','Sales');
INSERT INTO public.profiles(id,full_name,department_id,role,is_active,task_email_notifications) VALUES ('e2000000-0000-4000-8000-000000000001','Synthetic Sales','e3000000-0000-4000-8000-000000000001','EMPLOYEE',true,false);
INSERT INTO public.crm_deals(id,title,stage,workflow_status,approval_type,first_contact_date,contact_method,assigned_to) SELECT ('e1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'Synthetic legacy deal','PITCH','PENDING_APPROVAL','QUOTE',current_date,'PHONE','e2000000-0000-4000-8000-000000000001'::uuid FROM generate_series(1,12) n;
INSERT INTO public.crm_deal_approval_steps(deal_id,step_order,stage_key) SELECT id,n,(ARRAY['MARKETING_MANAGER','GENERAL_MANAGER','OPERATIONS_MANAGER'])[n] FROM public.crm_deals CROSS JOIN generate_series(1,3) n;
INSERT INTO public.crm_deal_attachments(deal_id,category,file_name,file_url) SELECT id,'QUOTATION','synthetic.pdf','storage://crm-deal-files/synthetic.pdf' FROM public.crm_deals;
INSERT INTO public.crm_deal_activity(deal_id,action,note) SELECT ('e1000000-0000-4000-8000-'||lpad(((n-1)%12+1)::text,12,'0'))::uuid,'SYNTHETIC','historical' FROM generate_series(1,52) n;
