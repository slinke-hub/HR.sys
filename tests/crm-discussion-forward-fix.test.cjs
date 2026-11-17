const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const app = fs.readFileSync(path.join(__dirname, '../js/app.js'), 'utf8');
const dbSource = fs.readFileSync(path.join(__dirname, '../js/db.js'), 'utf8');
const start = app.indexOf('function canContinueDealQuoteProposal(');
const end = app.indexOf('\nfunction renderDealWorkflowContents(', start);
assert(start >= 0 && end > start);
const ctx = { canonicalDealLifecycleStage: stage => stage };
vm.runInNewContext(app.slice(start, end), ctx);
const deal = {stage:'DISCUSSION', created_by:'sales', assignee_ids:[]};
const eligible = (d, workflow = {}, user = {id:'sales'}, profile = {is_active:true}, canUseCrm = true) => ctx.canContinueDealQuoteProposal({deal:d, canUseCrm}, workflow, user, profile);
assert.equal(eligible(deal), true);
assert.equal(eligible({...deal, stage:'NEGOTIATION'}), false);
assert.equal(eligible({...deal, design_task_id:'task'}), false);
assert.equal(eligible(deal, {designTask:{id:'task'}}), false);
assert.equal(eligible(deal, {error:true}), false);
assert.equal(eligible(deal, {}, {id:'other'}), false);
assert.equal(eligible(deal, {}, {id:'sales'}, {is_active:false}), false);
assert.equal(eligible(deal, {}, {id:'sales'}, {}, false), false);
const methodStart = dbSource.indexOf('    async replaceDealPresentationAttachments(');
const methodEnd = dbSource.indexOf('\n    },', methodStart);
assert(methodStart >= 0 && methodEnd > methodStart);
const calls = [];
const storage = {upload:async () => ({error:null}), remove:async () => ({error:null})};
const client = {storage:{from:() => storage}, rpc:async (name) => {calls.push(name); return {data:{id:'new'}, error:null};}};
const obj = vm.runInNewContext(`({${dbSource.slice(methodStart,methodEnd)}\n}})`, {
  supabaseClient:client, validateStorageUploadFile:()=>null, crypto:{randomUUID:()=> 'synthetic'},
  createStorageReference:()=> 'synthetic', console, Date
});
(async () => {
  const entries = [{file:{name:'synthetic.pdf', size:1}, category:'QUOTATION'}];
  assert.equal((await obj.replaceDealPresentationAttachments('deal','sales',entries,{preserveExisting:true})).success,true);
  assert.deepEqual(calls,['register_crm_deal_attachment_secure']);
  calls.length = 0;
  assert.equal((await obj.replaceDealPresentationAttachments('deal','sales',entries,{})).success,true);
  assert.deepEqual(calls,['register_crm_deal_attachment_secure','archive_crm_deal_attachments']);
  assert.match(app, /preserveExisting:\s*true/);
  console.log('DISCUSSION_ACTION_AND_DOCUMENT_PRESERVATION=PASS');
})().catch(error => {console.error(error); process.exitCode=1;});
