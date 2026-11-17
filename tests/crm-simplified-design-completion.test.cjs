const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '..', 'js', 'app.js'), 'utf8');
const start = source.indexOf('window.handleCompleteAndHandOffTask = async function (taskId) {');
const end = source.indexOf('\nwindow.handleEmployeeDocumentTypeChange', start);
assert.ok(start >= 0 && end > start);
async function scenario(kind, statusResult) {
  const calls = [];
  const task = {id:'synthetic',crm_workflow_kind:kind};
  const window = {activeTaskDetail:task, taskCache:{synthetic:task}, viewHTMLCache:{},
    requestTaskCompletionNote:async()=> 'Synthetic completion',
    handleUpdateTaskStatus:async(id,status)=>{calls.push(['status',id,status]);return statusResult;},
    closeTaskDetailsModal:()=>calls.push(['close'])};
  const db = {completeAndHandOffTask:async(id)=>{calls.push(['handoff',id]);return {success:true,data:{}};},
    addTaskComment:async()=>{calls.push(['comment']);return {success:true};}};
  const context={window,db,currentUser:{id:'synthetic-user'},currentView:'tasks',showToast:()=>{},taskDetailText:a=>a,renderView:async()=>{}};
  vm.runInNewContext(source.slice(start,end),context);
  await window.handleCompleteAndHandOffTask('synthetic');
  return calls;
}
(async()=>{
  assert.deepEqual(await scenario('QUOTE_PROPOSAL',{}),[['status','synthetic','completed'],['comment'],['close']]);
  assert.deepEqual(await scenario('QUOTE_PROPOSAL',{error:new Error('cancelled')}),[['status','synthetic','completed']]);
  assert.deepEqual(await scenario(null,{}),[['handoff','synthetic'],['comment'],['close']]);
  console.log('DESIGN_COMPLETION_ROUTING=PASS');
})().catch(e=>{console.error(e);process.exitCode=1;});
