'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
module.exports=async function(rt,container) {
  const sql=`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',false);
  DO $$ DECLARE d jsonb; BEGIN
    d:=public.create_crm_deal_secure(jsonb_build_object('title','Synthetic concurrency deal','client_id','30000000-0000-4000-8000-000000000001','first_contact_date','2026-11-01','contact_method','PHONE','assignee_ids',jsonb_build_array('10000000-0000-4000-8000-000000000001')));
    PERFORM public.change_crm_deal_stage((d->>'id')::uuid,'QUALIFICATION');
  END $$;`;
  rt.run('psql',['-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',sql],container);
  const ids=rt.run('psql',['-U','postgres','-d','postgres','-At','-c',`SELECT d.id||'|'||m.task_id FROM public.crm_deals d JOIN public.crm_generated_tasks m ON m.deal_id=d.id WHERE d.title='Synthetic concurrency deal' AND m.kind='CONTACT_DISCUSSION';`],container).trim().split('|');
  assert.equal(ids.length,2); for(const x of ids)assert.match(x,/^[0-9a-f-]{36}$/i);
  const [deal,task]=ids, user1='10000000-0000-4000-8000-000000000001', user2='10000000-0000-4000-8000-000000000002';
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hrsys-concurrency-'));
  const paths=[];
  const session=(name,script)=>{
    const f=path.join(dir,name+'.sql');paths.push(f);fs.writeFileSync(f,script,'utf8');
    const child=rt.spawnPsql(container,['-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres','-f',f]);
    const s={child,stdout:'',stderr:''};child.stdout.on('data',x=>s.stdout+=x);child.stderr.on('data',x=>s.stderr+=x);
    s.done=new Promise(resolve=>child.once('close',resolve));
    s.wait=async marker=>{for(let i=0;i<100;i++){if(s.stdout.includes(marker))return;if(child.exitCode!==null)throw Error('Concurrency session stopped before marker');await sleep(50);}throw Error('Concurrency marker timeout');};return s;
  };
  try {
    const holder=session('reassign',`BEGIN; UPDATE public.crm_deals SET assignee_ids=ARRAY['${user2}'::uuid] WHERE id='${deal}'; \\echo REASSIGN_HELD\nSELECT pg_sleep(1.5); COMMIT;`);
    await holder.wait('REASSIGN_HELD');
    const stale=session('stale',`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user1}',false); SELECT public.execute_crm_contact_discussion_task('${task}','START');`);
    await sleep(200);assert.equal(stale.child.exitCode,null,'Stale execution did not wait');assert.equal(await holder.done,0);assert.notEqual(await stale.done,0);assert.match(stale.stderr,/Only a current CRM deal assignee/);
    rt.run('psql',['-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',`UPDATE public.crm_deals SET assignee_ids=ARRAY['${user1}'::uuid] WHERE id='${deal}';`],container);
    const executor=session('execute',`SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user1}',false); BEGIN; SELECT public.execute_crm_contact_discussion_task('${task}','START'); \\echo EXECUTION_HELD\nSELECT pg_sleep(1.5); COMMIT;`);
    await executor.wait('EXECUTION_HELD');
    const reassign=session('after',`BEGIN; UPDATE public.crm_deals SET assignee_ids=ARRAY['${user2}'::uuid] WHERE id='${deal}'; COMMIT;`);
    await sleep(200);assert.equal(reassign.child.exitCode,null,'Reassignment did not wait');assert.equal(await executor.done,0);assert.equal(await reassign.done,0);
    console.log('CANDIDATE_TWO_SESSION_CONCURRENCY=PASS');
  } finally {for(const f of paths)if(fs.existsSync(f))fs.unlinkSync(f);fs.rmdirSync(dir);}
};
