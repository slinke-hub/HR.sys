/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

let rpcCall = null;
let clientConfig = null;
const stagingRef = 'jcfyyxsuspukcmybyhjj';
const stagingAnonKey = `header.${Buffer.from(JSON.stringify({ ref: stagingRef, role: 'anon' })).toString('base64url')}.signature`;
const windowObject = {
    HR_RUNTIME_CONFIG: {
        mode: 'staging',
        valid: true,
        projectRef: stagingRef,
        supabaseUrl: `https://${stagingRef}.supabase.co`,
        anonKey: stagingAnonKey
    },
    atob: value => Buffer.from(value, 'base64').toString('binary')
};
const radarRows = [
    { employee_id: '1', full_name: 'Clocked In User', clock_in_time: '2026-09-05T06:00:00Z', clock_out_time: null },
    { employee_id: '2', full_name: 'Clocked Out User', clock_in_time: '2026-09-05T05:00:00Z', clock_out_time: '2026-09-05T12:00:00Z' }
];
const context = {
    window: windowObject,
    supabase: {
        createClient(url, key) {
            clientConfig = { url, key };
            return {
            rpc(name, params) {
                rpcCall = { name, params };
                return Promise.resolve({ data: radarRows, error: null });
            }
            };
        }
    },
    console: { ...console, error() {} },
    Date,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval
};
vm.createContext(context);
const dbSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'db.js'), 'utf8');
const resolverSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'runtime-config-resolver.js'), 'utf8');
vm.runInContext(resolverSource, context);
vm.runInContext(`${dbSource}\nglobalThis.__testDb = db;`, context);

(async () => {
    const result = await context.__testDb.fetchEmployeesRadarAttendance();
    assert.equal(clientConfig.url, `https://${stagingRef}.supabase.co`);
    assert.equal(clientConfig.key, stagingAnonKey);
    assert.equal(rpcCall.name, 'get_employees_radar');
    assert.match(rpcCall.params.p_date, /^\d{4}-\d{2}-\d{2}$/);
    assert.deepEqual(JSON.parse(JSON.stringify(result)), radarRows);

    const appSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
    const componentStyles = fs.readFileSync(path.join(__dirname, '..', 'css', 'components.css'), 'utf8');
    const migrationSource = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260905133000_executive_employees_radar.sql'), 'utf8');
    for (const executive of ['GENERAL MANAGER', 'GM', 'CEO', 'CHIEF EXECUTIVE OFFICER']) {
        assert.match(appSource, new RegExp(`'${executive}'`));
        assert.match(migrationSource, new RegExp(`'${executive}'`));
    }
    assert.match(appSource, /isClockedOut \? 'Clocked out' : 'Clocked in'/);
    assert.match(appSource, /fetchEmployeesRadarAttendance\(\)/);
    assert.match(appSource, /window\.openEmployeesRadarClockOut = function/);
    assert.match(appSource, /window\.handleEmployeesRadarClockOut = async function/);
    assert.match(appSource, /!isClockedOut && isTaskAdmin\(\)/);
    assert.match(appSource, /db\.updateAttendancePunch\(attendanceId, 'OUT'/);
    assert.match(appSource, /onlyIfOpen: true/);
    assert.match(dbSource, /changes\.onlyIfOpen/);
    assert.match(appSource, /window\.refreshEmployeesRadar/);
    assert.match(componentStyles, /\.employees-radar-clockout \{/);
    assert.match(componentStyles, /\.employees-radar-card \.employees-radar-subtitle[\s\S]*?var\(--text-secondary\)/);
    assert.match(migrationSource, /CREATE POLICY employees_radar_company_attendance_select/);
    assert.match(migrationSource, /CREATE OR REPLACE FUNCTION public\.get_employees_radar/);

    console.log('Employees Radar access tests passed.');
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
