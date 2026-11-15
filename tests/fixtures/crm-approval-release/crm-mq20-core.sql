GRANT USAGE ON SCHEMA auth TO authenticated;
      INSERT INTO auth.users(id) VALUES ('10000000-0000-4000-8000-000000000001'),('10000000-0000-4000-8000-000000000002'),('10000000-0000-4000-8000-000000000003');
      INSERT INTO public.departments(id,name) VALUES ('20000000-0000-4000-8000-000000000001','Synthetic Sales'),('20000000-0000-4000-8000-000000000002','Synthetic Operations');
      INSERT INTO public.profiles(id,full_name,employee_id,department_id,role,is_active,task_email_notifications) VALUES
        ('10000000-0000-4000-8000-000000000001','Synthetic Primary','MQ-20','20000000-0000-4000-8000-000000000001','EMPLOYEE',true,false),
        ('10000000-0000-4000-8000-000000000002','Synthetic Secondary',NULL,'20000000-0000-4000-8000-000000000001','EMPLOYEE',true,false),
        ('10000000-0000-4000-8000-000000000003','Synthetic Unauthorized',NULL,'20000000-0000-4000-8000-000000000002','EMPLOYEE',true,false);
      INSERT INTO public.crm_clients(id,name) VALUES ('30000000-0000-4000-8000-000000000001','Synthetic Client');
      DO $$ BEGIN
        IF NOT public.can_access_crm('10000000-0000-4000-8000-000000000001') OR NOT public.can_access_crm('10000000-0000-4000-8000-000000000002') OR public.can_access_crm('10000000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Synthetic CRM role check failed'; END IF;
      END $$;
      SET ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      DO $$ DECLARE d jsonb; BEGIN
        d := public.create_crm_deal_secure(jsonb_build_object('title','Synthetic isolated acceptance','client_id','30000000-0000-4000-8000-000000000001','first_contact_date','2026-11-01','contact_method','PHONE','assignee_ids',jsonb_build_array('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002')));
        PERFORM set_config('test.deal', d->>'id', false);
        PERFORM public.change_crm_deal_stage((d->>'id')::uuid,'QUALIFICATION');
      END $$;
      RESET ROLE;
      DO $$ DECLARE t uuid; BEGIN
        SELECT task_id INTO STRICT t FROM public.crm_generated_tasks WHERE deal_id=current_setting('test.deal')::uuid AND kind='CONTACT_DISCUSSION';
        PERFORM set_config('test.task', t::text, false);
        IF (SELECT count(*) FROM public.tasks WHERE crm_deal_id=current_setting('test.deal')::uuid AND crm_workflow_kind='CONTACT_DISCUSSION') <> 1 THEN RAISE EXCEPTION 'Duplicate Contact Discussion task'; END IF;
        IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE id=t AND assignee_ids=ARRAY['10000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000002'::uuid]) THEN RAISE EXCEPTION 'Multi-assignee task differs from deal'; END IF;
      END $$;
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN
          INSERT INTO public.tasks(id,title,created_by,assignee_id,assignee_ids,crm_deal_id,crm_workflow_kind)
          VALUES ('40000000-0000-4000-8000-000000000001','Synthetic forged task','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001',ARRAY['10000000-0000-4000-8000-000000000001'::uuid],current_setting('test.deal')::uuid,'CONTACT_DISCUSSION');
        EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Direct Contact creation was not denied'; END IF;
      END $$;
      SET ROLE authenticated;
      DO $$ BEGIN PERFORM public.change_crm_deal_stage(current_setting('test.deal')::uuid,'QUALIFICATION'); END $$;
      DO $$ BEGIN IF (SELECT count(*) FROM public.tasks WHERE crm_deal_id=current_setting('test.deal')::uuid AND crm_workflow_kind='CONTACT_DISCUSSION') <> 1 THEN RAISE EXCEPTION 'Retry created a duplicate task'; END IF; END $$;
      DO $$ BEGIN PERFORM public.update_crm_deal_secure(current_setting('test.deal')::uuid,jsonb_build_object('assignee_ids',jsonb_build_array('10000000-0000-4000-8000-000000000002'))); END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN PERFORM public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'START'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Removed assignee could execute task'; END IF;
        IF EXISTS (SELECT 1 FROM public.tasks WHERE id=current_setting('test.task')::uuid) THEN RAISE EXCEPTION 'Removed assignee retained task visibility'; END IF;
      END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN PERFORM public.change_crm_deal_stage(current_setting('test.deal')::uuid,'QUALIFICATION'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Unauthorized CRM stage change allowed'; END IF;
      END $$;
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN PERFORM public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'START'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Unauthorized employee could execute task'; END IF;
      END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      DO $$ BEGIN PERFORM public.update_crm_deal_secure(current_setting('test.deal')::uuid,jsonb_build_object('assignee_ids',jsonb_build_array('10000000-0000-4000-8000-000000000001'))); END $$;
      RESET ROLE;
      INSERT INTO public.task_attachments(id,task_id,user_id,file_url,file_name)
        VALUES ('50000000-0000-4000-8000-000000000005',current_setting('test.task')::uuid,'10000000-0000-4000-8000-000000000002','storage://task-attachments/synthetic/contact.txt','contact.txt');
      INSERT INTO public.task_attachments(id,task_id,user_id,file_url,file_name,is_archived)
        VALUES ('50000000-0000-4000-8000-000000000006',current_setting('test.task')::uuid,'10000000-0000-4000-8000-000000000002','storage://task-attachments/synthetic/contact-old.txt','contact-old.txt',true);
      SET ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
      DO $$ BEGIN
        IF NOT public.can_read_task_attachment_file('synthetic/contact.txt',auth.uid()) THEN RAISE EXCEPTION 'Assigned MQ-20 user lost Contact attachment read'; END IF;
        IF NOT EXISTS (SELECT 1 FROM public.task_attachments WHERE id='50000000-0000-4000-8000-000000000005') THEN RAISE EXCEPTION 'Assigned MQ-20 user cannot list Contact attachment metadata'; END IF;
        IF public.can_read_task_attachment_file('synthetic/contact-old.txt',auth.uid()) OR EXISTS (SELECT 1 FROM public.task_attachments WHERE id='50000000-0000-4000-8000-000000000006') THEN RAISE EXCEPTION 'Archived Contact attachment exposed'; END IF;
      END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      SELECT public.update_crm_deal_secure(current_setting('test.deal')::uuid,jsonb_build_object('assignee_ids',jsonb_build_array('10000000-0000-4000-8000-000000000002')));
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
      DO $$ BEGIN
        IF public.can_read_task_attachment_file('synthetic/contact.txt',auth.uid()) THEN RAISE EXCEPTION 'Removed MQ-20 assignee retained Contact attachment read'; END IF;
        IF EXISTS (SELECT 1 FROM public.task_attachments WHERE id='50000000-0000-4000-8000-000000000005') OR public.can_read_current_task_attachment('50000000-0000-4000-8000-000000000005') THEN RAISE EXCEPTION 'Removed MQ-20 assignee retained Contact attachment metadata'; END IF;
      END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      SELECT public.update_crm_deal_secure(current_setting('test.deal')::uuid,jsonb_build_object('assignee_ids',jsonb_build_array('10000000-0000-4000-8000-000000000001')));
      RESET ROLE;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      INSERT INTO public.tasks(id,title,created_by,assignee_id,status,department,sub_type)
        VALUES ('40000000-0000-4000-8000-000000000003','Synthetic successor','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','todo','Synthetic Other','Other');
      INSERT INTO public.task_dependencies(predecessor_task_id,successor_task_id,created_by)
        VALUES (current_setting('test.task')::uuid,'40000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002');
      INSERT INTO public.task_attachments(id,task_id,user_id,file_url,file_name)
        VALUES ('50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','storage://task-attachments/synthetic/test.txt','synthetic.txt');
      SET ROLE authenticated;
      DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM public.task_attachments WHERE id='50000000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Authorized task attachment unavailable'; END IF; END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
      DO $$ BEGIN IF EXISTS (SELECT 1 FROM public.task_attachments WHERE id='50000000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Unauthorized task attachment visible'; END IF; END $$;
      RESET ROLE;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      INSERT INTO public.projects(id,project_name,project_type,created_by,assigned_people)
        VALUES ('60000000-0000-4000-8000-000000000001','Synthetic project','Other','10000000-0000-4000-8000-000000000002',ARRAY['10000000-0000-4000-8000-000000000003'::uuid]);
      INSERT INTO public.tasks(id,title,created_by,assignee_id,status,department,sub_type,project_id,visible_to)
        VALUES ('40000000-0000-4000-8000-000000000004','Synthetic shared task','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','todo','Synthetic Other','Other','60000000-0000-4000-8000-000000000001',ARRAY['10000000-0000-4000-8000-000000000003'::uuid]);
      INSERT INTO public.task_attachments(id,task_id,user_id,file_url,file_name,visible_to_project_assignee)
        VALUES ('50000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002','storage://task-attachments/synthetic/shared.txt','shared.txt',true),
               ('50000000-0000-4000-8000-000000000003','40000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002','storage://task-attachments/synthetic/private.txt','private.txt',false);
      INSERT INTO public.task_attachments(id,task_id,user_id,file_url,file_name,visible_to_project_assignee,is_archived)
        VALUES ('50000000-0000-4000-8000-000000000004','40000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002','storage://task-attachments/synthetic/archived.txt','archived.txt',true,true);
      SET ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
      DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.task_attachments WHERE id='50000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Shared attachment not visible to project assignee'; END IF;
        IF EXISTS (SELECT 1 FROM public.task_attachments WHERE id='50000000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Private attachment metadata visible'; END IF;
        IF EXISTS (SELECT 1 FROM public.task_attachments WHERE id='50000000-0000-4000-8000-000000000004') THEN RAISE EXCEPTION 'Archived attachment metadata visible'; END IF;
        IF NOT public.can_read_task_attachment_file('synthetic/shared.txt',auth.uid()) THEN RAISE EXCEPTION 'Shared attachment Storage helper denied project assignee'; END IF;
        IF public.can_read_task_attachment_file('synthetic/private.txt',auth.uid()) THEN RAISE EXCEPTION 'Private attachment Storage helper permits project assignee'; END IF;
        IF public.can_read_task_attachment_file('synthetic/archived.txt',auth.uid()) THEN RAISE EXCEPTION 'Archived attachment Storage helper permits project assignee'; END IF;
        IF public.can_read_task_attachment_file('synthetic/private.txt','10000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Attachment helper permitted arbitrary-user probing'; END IF;
        IF public.can_manage_task_attachments('40000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Attachment manager permitted arbitrary-user probing'; END IF;
        IF public.current_user_linked_project_task('40000000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Project helper permitted unrelated task probing'; END IF;
        IF has_table_privilege('authenticated','public.projects','SELECT') THEN RAISE EXCEPTION 'Projects SELECT broadened'; END IF;
      END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      DO $$ BEGIN IF NOT public.can_manage_task_attachments('40000000-0000-4000-8000-000000000004',auth.uid()) OR NOT public.can_read_task_attachment_file('synthetic/private.txt',auth.uid()) THEN RAISE EXCEPTION 'Task owner lost attachment management or read'; END IF; END $$;
      SELECT set_config('request.jwt.claim.sub','',false);
      DO $$ BEGIN IF public.can_read_task_attachment_file('synthetic/private.txt','10000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Missing authenticated subject enabled arbitrary-user probing'; END IF; END $$;
      DO $$ BEGIN IF public.can_manage_task_attachments('40000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Missing authenticated subject enabled management probing'; END IF; END $$;
      RESET ROLE;
      SET ROLE service_role;
      DO $$ BEGIN IF NOT public.can_manage_task_attachments('40000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002') OR NOT public.can_read_task_attachment_file('synthetic/private.txt','10000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Trusted service attachment path was lost'; END IF; END $$;
      RESET ROLE;
      SELECT set_config('test.notifications',(SELECT count(*)::text FROM public.notifications WHERE task_id=current_setting('test.task')::uuid),false);
      SELECT set_config('test.outbox',(SELECT count(*)::text FROM public.task_email_outbox WHERE task_id=current_setting('test.task')::uuid),false);
      SET ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',false);
      DO $$ DECLARE s text; BEGIN SELECT status INTO s FROM public.tasks WHERE id=current_setting('test.task')::uuid; RAISE NOTICE 'SYNTHETIC_TASK_STATUS=%', coalesce(s,'<not visible>'); END $$;
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN PERFORM public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'INVALID'); EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Invalid action allowed'; END IF;
      END $$;
      SELECT set_config('app.hrsys_mq20_task_context','70000000-0000-4000-8000-000000000001',false);
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN INSERT INTO public.task_waiting_history(task_id,actor_id,category,started_at) VALUES (current_setting('test.task')::uuid,auth.uid(),'CLIENT',now()); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Direct waiting history insertion allowed'; END IF;
      END $$;
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN INSERT INTO public.task_blocker_history(task_id,actor_id,category,created_at) VALUES (current_setting('test.task')::uuid,auth.uid(),'OTHER',now()); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Direct blocker history insertion allowed'; END IF;
      END $$;
      DO $$ DECLARE affected integer:=0; BEGIN
        BEGIN UPDATE public.tasks SET title='Unauthorized direct edit' WHERE id=current_setting('test.task')::uuid; GET DIAGNOSTICS affected=ROW_COUNT; EXCEPTION WHEN insufficient_privilege THEN affected:=0; END;
        IF affected<>0 THEN RAISE EXCEPTION 'Direct MQ-20 task edit allowed'; END IF;
      END $$;
      SELECT public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'START');
      SELECT public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'WAIT','CLIENT','Synthetic wait');
      SELECT public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'BLOCK','OTHER','Synthetic block');
      SELECT public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'RESUME');
      SELECT public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'COMPLETE');
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN PERFORM public.execute_crm_contact_discussion_task(current_setting('test.task')::uuid,'START'); EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Completed Contact task could be restarted'; END IF;
      END $$;
      RESET ROLE;
      DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.task_waiting_history WHERE task_id=current_setting('test.task')::uuid AND category='CLIENT') THEN RAISE EXCEPTION 'Scoped waiting history missing'; END IF;
        IF NOT EXISTS (SELECT 1 FROM public.task_blocker_history WHERE task_id=current_setting('test.task')::uuid AND category='OTHER') THEN RAISE EXCEPTION 'Scoped blocker history missing'; END IF;
      END $$;
      DO $$ BEGIN
        IF (SELECT count(*) FROM public.notifications WHERE task_id=current_setting('test.task')::uuid) <> current_setting('test.notifications')::integer
           OR (SELECT count(*) FROM public.task_email_outbox WHERE task_id=current_setting('test.task')::uuid) <> current_setting('test.outbox')::integer THEN
          RAISE EXCEPTION 'MQ-20 execution emitted notifications or outbox';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE id='40000000-0000-4000-8000-000000000003' AND status='todo' AND started_at IS NULL) THEN RAISE EXCEPTION 'MQ-20 completion changed successor'; END IF;
      END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      DO $$ DECLARE s text; BEGIN
        INSERT INTO public.tasks(id,title,created_by,assignee_id,status,department,sub_type)
          VALUES ('40000000-0000-4000-8000-000000000002','Synthetic Marketing Design','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','todo','Marketing','Designing Task');
        SELECT status INTO s FROM public.tasks WHERE id='40000000-0000-4000-8000-000000000002';
        IF s IS DISTINCT FROM 'review' THEN RAISE EXCEPTION 'Marketing Design review behavior changed'; END IF;
      END $$;
      SET ROLE authenticated;
      DO $$ DECLARE d jsonb; denied boolean:=false; BEGIN
        d:=public.get_crm_deal_secure(current_setting('test.deal')::uuid);
        IF d->>'id' IS DISTINCT FROM current_setting('test.deal') THEN RAISE EXCEPTION 'Authorized deal read failed'; END IF;
        PERFORM public.update_crm_deal_secure(current_setting('test.deal')::uuid,jsonb_build_object('title','Synthetic updated deal'));
        d:=public.get_crm_deal_secure(current_setting('test.deal')::uuid);
        IF d->>'title' IS DISTINCT FROM 'Synthetic updated deal' THEN RAISE EXCEPTION 'Authorized deal update failed'; END IF;
        d:=public.create_crm_deal_secure(jsonb_build_object('title','Synthetic lost workflow','client_id','30000000-0000-4000-8000-000000000001','first_contact_date','2026-11-01','contact_method','PHONE','assignee_ids',jsonb_build_array('10000000-0000-4000-8000-000000000002')));
        PERFORM set_config('test.lost_deal',d->>'id',false);
        BEGIN PERFORM public.mark_crm_deal_lost((d->>'id')::uuid,''); EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Lost without reason allowed'; END IF;
        PERFORM public.mark_crm_deal_lost((d->>'id')::uuid,'Synthetic reason');
        denied:=false;
        BEGIN PERFORM public.update_crm_deal_secure((d->>'id')::uuid,jsonb_build_object('title','Forbidden lost update')); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Lost deal edit allowed'; END IF;
      END $$;
      RESET ROLE;
      DO $$ BEGIN IF (SELECT stage FROM public.crm_deals WHERE id=current_setting('test.lost_deal')::uuid)<>'LOST' THEN RAISE EXCEPTION 'Lost transition failed'; END IF; END $$;
      SET ROLE authenticated;
      DO $$ DECLARE d jsonb; BEGIN
        d:=public.create_crm_deal_secure(jsonb_build_object('title','Synthetic approval workflow','client_id','30000000-0000-4000-8000-000000000001','first_contact_date','2026-11-01','contact_method','PHONE','assignee_ids',jsonb_build_array('10000000-0000-4000-8000-000000000002')));
        PERFORM set_config('test.approval_deal',d->>'id',false);
      END $$;
      RESET ROLE;
      UPDATE public.crm_deals SET approval_type='QUOTE',workflow_status='PENDING_APPROVAL' WHERE id=current_setting('test.approval_deal')::uuid;
      INSERT INTO public.crm_deal_approval_steps(id,deal_id,step_order,stage_key,approver_id,status)
        VALUES ('80000000-0000-4000-8000-000000000001',current_setting('test.approval_deal')::uuid,1,'MARKETING_MANAGER','10000000-0000-4000-8000-000000000002','PENDING');
      SET ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',false);
      DO $$ DECLARE denied boolean:=false; BEGIN
        BEGIN PERFORM public.decide_deal_approval('80000000-0000-4000-8000-000000000001','APPROVED',NULL); EXCEPTION WHEN raise_exception OR insufficient_privilege THEN denied:=true; END;
        IF NOT denied THEN RAISE EXCEPTION 'Unauthorized deal approval allowed'; END IF;
      END $$;
      SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
      SELECT public.decide_deal_approval('80000000-0000-4000-8000-000000000001','APPROVED',NULL);
      RESET ROLE;
      DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.crm_deals WHERE id=current_setting('test.approval_deal')::uuid AND stage='NEGOTIATION' AND workflow_status='APPROVED') THEN RAISE EXCEPTION 'Approved deal did not transition to Negotiation'; END IF;
      END $$;