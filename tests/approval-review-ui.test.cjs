'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const puppeteer=require('puppeteer');
const s=fs.readFileSync(path.join(__dirname,'../js/app.js'),'utf8');
const a=s.indexOf('window.openAssignedCrmApprovalReview = async function (stepId) {');
const b=s.indexOf('window.openDealWorkflowModal = async function',a);
assert(a>=0&&b>a,'Draft review function missing');
(async()=>{
 const browser=await puppeteer.launch({headless:true,executablePath:process.env.PUPPETEER_EXECUTABLE_PATH,args:['--no-sandbox']});
 try{
  const page=await browser.newPage();await page.setContent('<!doctype html><html><body></body></html>');
  await page.evaluate(()=>{
   window.currentUser={id:'synthetic-user'};
   window.taskDetailText=(en,_ar)=>en;window.escapeHTML=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
   window.showToast=()=>{};window.db={
    fetchPendingCrmApprovals:async()=>[{id:'step1',approver_id:'synthetic-user',deal_id:'deal1',deal:{id:'deal1',title:'Synthetic',amount:null,crm_clients:{name:'Client'}}}],
    fetchMyCrmApprovalDocuments:async()=>({success:true,data:[{id:'doc1',deal_id:'deal1',file_name:'quote.pdf'},{id:'wrong',deal_id:'other',file_name:'private.pdf'}]}),
    downloadMyCrmApprovalDocument:async()=>({success:false})
   };
  });
  await page.addScriptTag({content:s.slice(a,b)});
  await page.evaluate(()=>window.openAssignedCrmApprovalReview('step1'));
  assert.equal(await page.$eval('[role="dialog"] h2',el=>el.textContent),'Synthetic');
  const text=await page.$eval('[role="dialog"]',el=>el.textContent);
  assert.match(text,/quote\.pdf/);assert.doesNotMatch(text,/private\.pdf|Amount/);
  await page.click('[data-close]');assert.equal(await page.$('[role="dialog"]'),null);
  await page.evaluate(()=>window.openAssignedCrmApprovalReview('wrong'));assert.equal(await page.$('[role="dialog"]'),null);
  console.log('APPROVAL_REVIEW_BROWSER_DRAFT=PASS');
 } finally {await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1});
