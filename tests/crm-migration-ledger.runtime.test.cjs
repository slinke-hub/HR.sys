'use strict';
const rt=require('./helpers/postgres-docker-runtime.cjs'),verify=require('./helpers/crm-migration-ledger.cjs');
const versions=['20261111100000','20261112100000','20261112110000','20261112120000','20261113100000','20261115120000','20261115130000'];
(async()=>{let n;try{n=(await rt.start('hrsys-local-ledger')).name;await verify(rt,n,versions)}finally{rt.stop(n)}})().catch(e=>{console.error('SYNTHETIC_CLI_LEDGER=FAIL '+e.message);process.exitCode=1});
