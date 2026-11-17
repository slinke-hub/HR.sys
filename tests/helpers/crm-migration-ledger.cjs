'use strict';
const assert=require('node:assert/strict'),net=require('node:net'),cp=require('node:child_process');
module.exports=async function verifyLocalLedger(rt,n,versions){let server;try{
 rt.run('psql',['-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-c',"ALTER USER postgres PASSWORD 'synthetic_ledger_only'"],n);
 server=net.createServer(socket=>{const c=cp.spawn('docker',['exec','-i',n,'bash','-c','exec 3<>/dev/tcp/127.0.0.1/5432; cat <&3 & cat >&3'],{stdio:['pipe','pipe','ignore'],windowsHide:true});socket.pipe(c.stdin);c.stdout.pipe(socket);socket.on('error',()=>c.kill());socket.on('close',()=>c.kill());c.on('exit',()=>socket.destroy());c.on('error',()=>socket.destroy())});
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});const port=server.address().port;
 const runCli=()=>new Promise((resolve,reject)=>{const c=cp.spawn(process.platform==='win32'?'supabase.exe':'supabase',['migration','repair','--db-url',`postgresql://postgres:synthetic_ledger_only@127.0.0.1:${port}/postgres?sslmode=disable`,'--status','applied',...versions,'--yes'],{stdio:'ignore',windowsHide:true});const timer=setTimeout(()=>{c.kill();reject(Error('Local CLI timeout'))},45000);c.on('error',e=>{clearTimeout(timer);reject(e)});c.on('exit',code=>{clearTimeout(timer);code===0?resolve():reject(Error('Local CLI ledger command failed'))})});
 await runCli();await runCli();
 const rows=rt.run('psql',['-U','postgres','-d','postgres','-At','-c',`SELECT version||'|'||count(*) FROM supabase_migrations.schema_migrations WHERE version IN (${versions.map(v=>"'"+v+"'").join(',')}) GROUP BY version ORDER BY version`],n).trim().split(/\r?\n/);
 assert.deepEqual(rows,versions.map(v=>v+'|1'));console.log('SYNTHETIC_CLI_LEDGER=PASS');
 }finally{if(server)await new Promise(resolve=>server.close(resolve));}};
