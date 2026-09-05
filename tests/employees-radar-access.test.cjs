/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

let rpcCall = null;
const radarRows = [
    { employee_id: '1', full_name: 'Clocked In User', clock_in_time: '2026-09-05T06:00:00Z', clock_out_time: null },
    { employee_id: '2', full_name: 'Clocked Out User', clock_in_time: '2026-09-05T05:00:00Z', clock_out_time: '2026-09-05T12:00:00Z' }
];
const context = {
    window: {},
    supabase: {
        createClient: () => ({
            rpc(name, params) {
                rpcCall = { name, params };
                return Promise.resolve({ data: radarRows, error: null });
            }
        })
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
vm.runInContext(`${dbSource}\nglobalThis.__testDb = db;`, context);

(async () => {
    const result = await context.__testDb.fetchEmployeesRadarAttendance();
    assert.equal(rpcCall.name, 'get_employees_radar');
    assert.match(rpcCall.params.p_date, /^\d{4}-\d{2}-\d{2}$/);
    assert.deepEqual(JSON.parse(JSON.stringify(result)), radarRows);

    const appSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
    const migrationSource = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '20260905133000_executive_employees_radar.sql'), 'utf8');
    for (const executive of ['GENERAL MANAGER', 'GM', 'CEO', 'CHIEF EXECUTIVE OFFICER']) {
        assert.match(appSource, new RegExp(`'${executive}'`));
        assert.match(migrationSource, new RegExp(`'${executive}'`));
    }
    assert.match(appSource, /isClockedOut \? 'Clocked out' : 'Clocked in'/);
    assert.match(appSource, /fetchEmployeesRadarAttendance\(\)/);
    assert.match(migrationSource, /CREATE POLICY employees_radar_company_attendance_select/);
    assert.match(migrationSource, /CREATE OR REPLACE FUNCTION public\.get_employees_radar/);

    console.log('Employees Radar access tests passed.');
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
