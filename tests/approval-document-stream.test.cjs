'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
let src=fs.readFileSync(path.join(__dirname,'../supabase/functions/approval-document-stream/index.ts'),'utf8');
src=src.replace(/^import .*;\s*$/m,'').replaceAll(': Request','').replaceAll(': string','');
const id='12345678-1234-4234-8234-123456789abc';
let handler,allowed=true,downloads=0,pathValue='storage://crm-deal-files/synthetic/document.pdf';
const fetch=async (url,options)=>{
 if(url.endsWith('/auth/v1/user'))return new Response('{}',{status:200});
 if(url.endsWith('/rest/v1/rpc/get_my_pending_crm_approval_document'))return new Response(JSON.stringify(allowed&&JSON.parse(options.body).p_document_id===id?{id,source:'DEAL',file_url:pathValue}:null),{status:200});
 if(url.endsWith('/storage/v1/object/authenticated/crm-deal-files/synthetic/document.pdf')){downloads++;assert.equal(options.headers.apikey,'synthetic-service');return new Response('synthetic',{status:200});}
 throw Error('Unexpected local mock route');
};
const Deno={env:{get:key=>({'SUPABASE_URL':'http://local.invalid','SUPABASE_ANON_KEY':'synthetic-anon','SUPABASE_SERVICE_ROLE_KEY':'synthetic-service'}[key]||'')},serve:fn=>handler=fn};
vm.runInNewContext(src,{Deno,fetch,Response,Request,URL,Blob});
const request=()=>new Request('http://local.invalid/approval-document',{method:'POST',headers:{authorization:'Bearer synthetic-token','content-type':'application/json',origin:'https://sys.muqam.net'},body:JSON.stringify({document_id:id,source:'DEAL'})});
(async()=>{
 let r=await handler(request());assert.equal(r.status,200);assert.equal(await r.text(),'synthetic');assert.match(r.headers.get('cache-control'),/no-store/);assert.equal(downloads,1);
 allowed=false;r=await handler(request());assert.equal(r.status,404);assert.equal(downloads,1,'Revoked caller must not trigger privileged download');
 allowed=true;pathValue='storage://crm-deal-files/../secret';r=await handler(request());assert.equal(r.status,404);assert.equal(downloads,1,'Invalid path must not trigger privileged download');
 r=await handler(new Request('http://local.invalid',{method:'POST',body:'{}'}));assert.equal(r.status,404);
 console.log('APPROVAL_DOCUMENT_PROXY_MOCK=PASS');
})().catch(e=>{console.error(e.message);process.exitCode=1});
