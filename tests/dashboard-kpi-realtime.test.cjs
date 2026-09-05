/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const responses = {
    profiles: { data: null, count: 24, error: null },
    attendance: { data: null, count: 1, error: null },
    tasks: {
        data: [
            { status: 'todo' },
            { status: 'Completed' },
            { status: 'Approved' },
            { status: 'in_progress' }
        ],
        count: null,
        error: null
    },
    requests: {
        data: [
            { status: 'PENDING' },
            { status: 'Pending Manager' },
            { status: 'APPROVED' }
        ],
        count: null,
        error: null
    }
};

function queryFor(table) {
    const query = {
        select() { return query; },
        eq() { return query; },
        is() { return query; },
        then(resolve, reject) { return Promise.resolve(responses[table]).then(resolve, reject); }
    };
    return query;
}

const context = {
    window: {},
    supabase: { createClient: () => ({ from: queryFor }) },
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
    const values = await context.__testDb.fetchDashboardKpiCounts();
    assert.deepEqual(JSON.parse(JSON.stringify(values)), {
        totalEmployees: 24,
        clockedInNow: 1,
        openTasks: 2,
        pendingRequests: 2
    });

    responses.tasks = { data: null, count: null, error: new Error('offline') };
    assert.equal(await context.__testDb.fetchDashboardKpiCounts(), null);

    const appSource = fs.readFileSync(path.join(__dirname, '..', 'js', 'app.js'), 'utf8');
    for (const table of ['profiles', 'attendance', 'tasks', 'requests']) {
        assert.match(appSource, new RegExp(`table: '${table}'`));
    }
    assert.match(appSource, /if \(viewId === 'dashboard'\) startDashboardKpiRealtime\(\)/);
    assert.match(appSource, /else stopDashboardKpiRealtime\(\)/);
    console.log('Dashboard KPI realtime tests passed.');
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
