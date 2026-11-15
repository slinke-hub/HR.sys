'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync(require('node:path').join(__dirname,'../js/app.js'),'utf8');
const a=src.indexOf('async function renderApprovals() {'),b=src.indexOf('\nwindow.setApprovalsTab',a);
assert(a>=0&&b>a,'Approvals renderer unavailable');
let queried=false,steps=[{id:'11111111-1111-4111-8111-111111111111',approver_id:'synthetic-reviewer',deal_id:'22222222-2222-4222-8222-222222222222',deal:{id:'22222222-2222-4222-8222-222222222222',title:'Synthetic own'}},{id:'33333333-3333-4333-8333-333333333333',approver_id:'different-reviewer',deal_id:'44444444-4444-4444-8444-444444444444',deal:{title:'Synthetic unrelated'}}];
const sandbox={currentUserProfile:{job_title:''},currentUserRole:'EMPLOYEE',currentUser:{id:'synthetic-reviewer'},isTaskAdmin:()=>false,escapeHTML:x=>String(x),taskDetailText:en=>en,
 db:{fetchPendingCrmApprovals:async()=>{queried=true;return steps}}};
vm.runInNewContext(src.slice(a,b)+'\nglobalThis.__render=renderApprovals;',sandbox);
(async()=>{let html=await sandbox.__render();assert.ok(queried,'Assigned reviewer must reach scoped lookup');assert.match(html,/Synthetic own/);assert.doesNotMatch(html,/Synthetic unrelated/);steps=[];html=await sandbox.__render();assert.match(html,/unauthorized_access/,'Unassigned ordinary employee must remain denied');console.log('ASSIGNED_APPROVER_ENTRY=PASS')})().catch(e=>{console.error(e.message);process.exitCode=1});
