'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const rt=require('./helpers/postgres-docker-runtime.cjs');
(async()=>{let n;const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hrsys-fingerprint-test-')),files=[];try{
 n=(await rt.start('hrsys-fingerprint-canonical')).name;const sql=(...args)=>rt.run('psql',['-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1',...args],n);
 const template="CREATE OR REPLACE FUNCTION public.synthetic_canonical_test() RETURNS integer LANGUAGE plpgsql AS $body$\nBEGIN\n  -- verified synthetic comment\n  RETURN 1;\nEND;\n$body$;\n";
 const read=()=>sql('-At','-c',"SELECT md5(pg_get_functiondef('public.synthetic_canonical_test()'::regprocedure))||'|'||md5(replace(replace(pg_get_functiondef('public.synthetic_canonical_test()'::regprocedure),E'\\r\\n',E'\\n'),E'\\r',E'\\n'))").trim().split('|');
 const apply=(name,text)=>{let f=path.join(dir,name+'.sql');fs.writeFileSync(f,text);files.push(f);sql('-f',f);return read()};
 const a=apply('lf',template),b=apply('crlf',template.replace(/\n/g,'\r\n')),c=apply('cr',template.replace(/\n/g,'\r'));
 assert.notEqual(a[0],b[0],'Raw fingerprints should detect original line endings');assert.equal(a[1],b[1]);assert.equal(a[1],c[1]);
 const comment=apply('comment',template.replace('verified synthetic comment','changed synthetic comment'));assert.notEqual(a[1],comment[1],'Comments must remain protected');
 const token=apply('token',template.replace('RETURN 1','RETURN 2'));assert.notEqual(a[1],token[1],'SQL token changes must remain protected');
 console.log('FINGERPRINT_CANONICALIZATION=PASS');
 }finally{rt.stop(n);for(const f of files)fs.unlinkSync(f);fs.rmdirSync(dir)}})().catch(e=>{console.error('FINGERPRINT_CANONICALIZATION=FAIL '+e.message);process.exitCode=1});
