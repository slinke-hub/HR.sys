-- HR.sys staging-only reference catalog. No users or business records are created.
BEGIN;

INSERT INTO public.departments (id, name, name_ar, is_active)
SELECT v.id, v.name, v.name_ar, true
FROM (VALUES
  ('10000000-0000-0000-0000-000000000001'::uuid, 'Administrative', 'الإدارة'),
  ('10000000-0000-0000-0000-000000000002'::uuid, 'Sales', 'المبيعات'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'Marketing', 'التسويق'),
  ('10000000-0000-0000-0000-000000000004'::uuid, 'Operations', 'العمليات')
) AS v(id, name, name_ar)
WHERE NOT EXISTS (SELECT 1 FROM public.departments d WHERE lower(d.name) = lower(v.name));

INSERT INTO public.job_titles (department_id, name, name_ar, job_level, is_active)
SELECT d.id, v.name, v.name_ar, v.job_level, true
FROM (VALUES
  ('Administrative','Owner',NULL::text,NULL::text),('Administrative','GM',NULL,NULL),
  ('Administrative','Accountant Manager',NULL,NULL),('Administrative','CEO',NULL,NULL),
  ('Administrative','HR Manager',NULL,NULL),('Administrative','Accountant Assistant',NULL,NULL),
  ('Administrative','Receptionist',NULL,NULL),('Administrative','Data Entry Clerk',NULL,NULL),
  ('Administrative','Administrative Assistant',NULL,NULL),('Administrative','Office Manager',NULL,NULL),
  ('Administrative','Executive Assistant (EA)',NULL,NULL),('Administrative','Facilities Coordinator',NULL,NULL),
  ('Administrative','Director of Administration',NULL,NULL),('Administrative','Chief Administrative Officer (CAO)',NULL,NULL),
  ('Administrative','IT Manager',NULL,NULL),('Administrative','IT Support Specialist',NULL,NULL),
  ('Administrative','System Administrator',NULL,NULL),('Administrative','Network Administrator',NULL,NULL),
  ('Administrative','Technician',NULL,NULL),
  ('Sales','Sales Specialist','أخصائي مبيعات','specialist'),
  ('Sales','Sales Employee','موظف مبيعات','employee')
) AS v(department_name, name, name_ar, job_level)
JOIN public.departments d ON lower(d.name) = lower(v.department_name)
WHERE NOT EXISTS (
  SELECT 1 FROM public.job_titles jt
  WHERE jt.department_id = d.id AND lower(jt.name) = lower(v.name)
);

INSERT INTO public.role_permissions (role, allowed_pages) VALUES
 ('EMPLOYEE','["dashboard","requests","time","tasks","documents","profile"]'::jsonb),
 ('MANAGER','["dashboard","requests","time","tasks","documents","profile","approvals"]'::jsonb),
 ('HR_MANAGER','["dashboard","requests","time","tasks","documents","profile","approvals","leave_calculator","employees","custody_handover"]'::jsonb),
 ('ADMIN','["dashboard","tasks","requests","time","documents","expenses","performance","projects","crm","clients","approvals","profile","notifications","admin","users","departments","translations","templates","analytics","leave_calculator","employees","custody_handover","payroll"]'::jsonb)
ON CONFLICT (role) DO UPDATE SET allowed_pages = EXCLUDED.allowed_pages, updated_at = timezone('utc', now());

COMMIT;
