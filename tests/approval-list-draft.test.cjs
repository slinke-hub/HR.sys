'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs');
const source=fs.readFileSync(require('node:path').join(__dirname,'../js/db.js'),'utf8');
const start=source.indexOf('    async fetchPendingCrmApprovals() {');
const end=source.indexOf('    async fetchPendingCrmDesignTaskApprovals()',start);
assert(start>=0&&end>start,'Approval list function missing');
const method=source.slice(start,end).trim().replace(/,\s*$/,'');
function makeDb({steps,deals,assigned,assignedError}){
 const chain={select(){return this},eq(){return this},order(){return Promise.resolve({data:steps,error:null})}};
 const client={from(){return chain},rpc(name){return Promise.resolve({data:name==='list_crm_deals_secure'?deals:assigned,error:name==='list_my_pending_crm_approval_context'?assignedError||null:null})}};
 return new Function('supabaseClient',`return ({${method}})`)(client);
}
(async()=>{
 const own={id:'step-own',deal_id:'deal-own',deal:{id:'deal-own',title:'Synthetic'}};
 let result=await makeDb({steps:[{id:'step-own',deal_id:'deal-own'}],deals:[],assigned:[own]}).fetchPendingCrmApprovals();
 assert.deepEqual(result,[own],'Non-CRM reviewer must receive assigned pending context');
 result=await makeDb({steps:[{id:'step-own',deal_id:'deal-own'}],deals:[{id:'deal-own',workflow_status:'PENDING_APPROVAL'}],assigned:[own]}).fetchPendingCrmApprovals();
 assert.equal(result.length,1,'CRM-visible steps must not be duplicated');
 result=await makeDb({steps:[],deals:[],assigned:[{id:'bad',deal_id:'one',deal:{id:'two'}}]}).fetchPendingCrmApprovals();
 assert.deepEqual(result,[],'Mismatched context must be ignored');
 result=await makeDb({steps:[{id:'s',deal_id:'d'}],deals:[{id:'d',workflow_status:'PENDING_APPROVAL'}],assigned:null,assignedError:{code:'PGRST202'}}).fetchPendingCrmApprovals();
 assert.equal(result.length,1,'Existing approval list must remain available before the new RPC exists');
 console.log('SCOPED_APPROVAL_LIST_LOCAL_TEST=PASS');
})().catch(e=>{console.error(e.message);process.exitCode=1});
