const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

const helperStart = app.indexOf('function normalizeTaskManagerIdentifier(value) {');
const helperEnd = app.indexOf('window.resolveTaskDepartmentManager = resolveTaskDepartmentManager;', helperStart);
assert.notEqual(helperStart, -1, 'manager identifier normalization helper exists');
assert.notEqual(helperEnd, -1, 'manager resolver is exposed for the UI');
const helperSource = app.slice(helperStart, helperEnd + 'window.resolveTaskDepartmentManager = resolveTaskDepartmentManager;'.length);
const sandbox = { window: {} };
vm.runInNewContext(`${helperSource}\nthis.resolve = resolveTaskDepartmentManager;`, sandbox);
const resolve = sandbox.resolve;

assert.match(app, /id="taskDepartmentManagerName" type="text" class="form-control" readonly aria-readonly="true"/);
assert.match(html, /id="editTaskDepartmentManagerName" class="form-control" type="text" readonly aria-readonly="true"/);
assert.match(app, /id="taskSupervisorId" type="hidden"/);
assert.match(html, /id="editTaskSupervisorId" type="hidden"/);
assert.match(app, /No department manager assigned/);
assert.match(app, /Manager assigned, name unavailable/);
assert.match(app, /Department manager data could not be loaded/);
assert.match(app, /nameInput\.value = managerName \|\| labels\[result\.state\]/);
assert.match(app, /employees = \(window\.taskAllUsersCache \|\| \[\]\)\.filter\(user => user\.department_id === department\.id\)/,
    'non-company-wide assignee choices remain department-scoped');
assert.match(app, /if \(task\.supervisor_id === currentUser\.id\) return true;/,
    'supervisor approval relationship remains based on task.supervisor_id');
assert.match(db, /rpc\('get_my_department_supervisors'\)/,
    'manager-name fallback reuses the existing caller-scoped supervisor RPC');

const headPrecedence = resolve(
    { id: 'dept-a', head_id: ' HEAD-ID ', manager_id: 'fallback-id' },
    [{ id: 'head-id', full_name: 'Head Name' }, { id: 'fallback-id', full_name: 'Fallback Name' }]
);
assert.equal(headPrecedence.managerId, 'HEAD-ID');
assert.equal(headPrecedence.manager.full_name, 'Head Name');
assert.equal(headPrecedence.state, 'resolved');

const staleHeadDoesNotSwitch = resolve(
    { id: 'dept-a', head_id: 'stale-head', manager_id: 'fallback-id' },
    [{ id: 'fallback-id', full_name: 'Fallback Name' }]
);
assert.equal(staleHeadDoesNotSwitch.managerId, 'stale-head');
assert.equal(staleHeadDoesNotSwitch.manager, null);
assert.equal(staleHeadDoesNotSwitch.state, 'name_unavailable');

const managerFallback = resolve(
    { id: 'dept-a', head_id: null, manager_id: ' MANAGER-ID ' },
    [{ id: 'manager-id', full_name: 'Manager Name' }]
);
assert.equal(managerFallback.managerId, 'MANAGER-ID');
assert.equal(managerFallback.manager.full_name, 'Manager Name');

const emptyHeadFallback = resolve(
    { id: 'dept-a', head_id: '  ', manager_id: 'manager-id' },
    [{ id: ' MANAGER-ID ', full_name: 'Manager Name' }]
);
assert.equal(emptyHeadFallback.state, 'resolved');
assert.equal(emptyHeadFallback.manager.full_name, 'Manager Name');

const missingManager = resolve({ id: 'dept-a', head_id: null, manager_id: null }, []);
assert.equal(missingManager.state, 'no_manager');
assert.equal(missingManager.managerId, '');

const staleProfile = resolve({ id: 'dept-a', head_id: 'missing-profile' }, []);
assert.equal(staleProfile.state, 'name_unavailable');
assert.equal(staleProfile.managerId, 'missing-profile');

const departmentLoadFailure = resolve(
    { id: 'dept-a', head_id: 'head-id' },
    [{ id: 'head-id', full_name: 'Head Name' }],
    { departmentsFailed: true }
);
assert.equal(departmentLoadFailure.state, 'load_error');

const profileLoadFailure = resolve(
    { id: 'dept-a', head_id: 'head-id' },
    [],
    { profilesFailed: true }
);
assert.equal(profileLoadFailure.state, 'load_error');

const ownDepartmentRpc = resolve(
    { id: 'dept-a', head_id: 'head-id' },
    [],
    {
        currentUserId: 'employee-id',
        ownDepartmentId: ' DEPT-A ',
        ownDepartmentSupervisors: [{ id: ' HEAD-ID ', full_name: 'Caller-Scoped Head' }]
    }
);
assert.equal(ownDepartmentRpc.manager.full_name, 'Caller-Scoped Head');
assert.equal(ownDepartmentRpc.state, 'resolved');

const otherDepartmentRpcIgnored = resolve(
    { id: 'dept-b', head_id: 'head-id' },
    [],
    {
        currentUserId: 'employee-id',
        ownDepartmentId: 'dept-a',
        ownDepartmentSupervisors: [{ id: 'head-id', full_name: 'Other Department Head' }]
    }
);
assert.equal(otherDepartmentRpcIgnored.manager, null);
assert.equal(otherDepartmentRpcIgnored.state, 'name_unavailable');

assert.match(app, /departmentsFailed: allDepartments\?\.loadFailed === true/);
assert.match(app, /profilesFailed: fetchedUsers\?\.loadFailed === true/);
assert.match(db, /Object\.defineProperty\(rows, 'loadFailed', \{ value: true, enumerable: false \}\)/);

const lifecycleStart = app.indexOf('let taskDirectoryRenderGeneration = 0;');
const lifecycleEnd = app.indexOf('async function renderTasks() {', lifecycleStart);
assert.notEqual(lifecycleStart, -1, 'task-directory generation guard exists');
assert.notEqual(lifecycleEnd, -1, 'task-directory guard precedes the async task render');
const lifecycleSource = app.slice(lifecycleStart, lifecycleEnd);
const fields = Object.fromEntries([
    'taskDepartmentManagerName', 'editTaskDepartmentManagerName', 'taskSupervisorId', 'editTaskSupervisorId'
].map(id => [id, { value: 'stale', dataset: { managerState: 'resolved' } }]));
const lifecycleSandbox = {
    window: {
        taskAllUsersCache: [{ id: 'old-user' }],
        taskDepartmentsCache: [{ id: 'old-dept' }],
        taskDepartmentSupervisors: [{ id: 'old-supervisor' }],
        taskCache: { old: { id: 'old-task' } },
        viewHTMLCache: { tasks: '<stale task UI>' }
    },
    document: { getElementById: id => fields[id] || null }
};
vm.runInNewContext(`
    let currentUser = { id: 'user-a' };
    let currentView = 'tasks';
    function normalizeTaskManagerIdentifier(value) { return String(value ?? '').trim().toLowerCase(); }
    function isTaskWorkspaceActive() { return currentView === 'tasks' || currentView === 'tasks_v2'; }
    ${lifecycleSource}
    this.api = {
        begin: beginTaskDirectoryLoad,
        current: isCurrentTaskDirectoryLoad,
        auth: updateTaskDirectoryAuthIdentity,
        setUser: id => { currentUser = id ? { id } : null; },
        setView: view => { currentView = view; }
    };
`, lifecycleSandbox);
const lifecycle = lifecycleSandbox.api;
const guardedApply = (context, field, value) => {
    if (!lifecycle.current(context)) return false;
    lifecycleSandbox.window[field] = value;
    return true;
};

const olderSameUserRender = lifecycle.begin();
const newerSameUserRender = lifecycle.begin();
assert.equal(lifecycle.current(olderSameUserRender), false, 'a newer render supersedes an older render for the same user');
assert.equal(lifecycle.current(newerSameUserRender), true);
assert.equal(guardedApply(olderSameUserRender, 'taskAllUsersCache', [{ id: 'stale' }]), false);
assert.equal(lifecycleSandbox.window.taskAllUsersCache.length, 0, 'first authenticated identity starts with an isolated empty directory cache');

const signedOutPendingRender = lifecycle.begin();
lifecycle.auth(null, true);
lifecycle.setUser(null);
assert.equal(lifecycle.current(signedOutPendingRender), false, 'sign-out invalidates pending task directory loads');
assert.deepEqual(Array.from(lifecycleSandbox.window.taskAllUsersCache), []);
assert.deepEqual(Array.from(lifecycleSandbox.window.taskDepartmentsCache), []);
assert.equal(lifecycleSandbox.window.viewHTMLCache.tasks, '');
for (const field of Object.values(fields)) {
    assert.equal(field.value, '');
    assert.equal(field.dataset.managerState, undefined);
}

lifecycle.auth('user-a');
lifecycle.setUser('user-a');
const userAPendingRender = lifecycle.begin();
lifecycle.auth('user-b');
assert.equal(lifecycle.current(userAPendingRender), false, 'user B session invalidates user A pending results');
assert.equal(lifecycle.begin(), null, 'old currentUser cannot start a render against the new authenticated identity');
lifecycle.setUser('user-b');
const userBRender = lifecycle.begin();
assert.equal(lifecycle.current(userBRender), true);
assert.equal(guardedApply(userAPendingRender, 'taskDepartmentsCache', [{ id: 'user-a-dept' }]), false);
assert.equal(lifecycleSandbox.window.taskDepartmentsCache.length, 0);

const lateRpcRender = lifecycle.begin();
const newerRpcRender = lifecycle.begin();
assert.equal(lifecycle.current(lateRpcRender), false, 'late supervisor RPC result is rejected with its originating render');
assert.equal(guardedApply(lateRpcRender, 'taskDepartmentSupervisors', [{ id: 'stale-supervisor' }]), false);
assert.equal(lifecycleSandbox.window.taskDepartmentSupervisors.length, 0);
lifecycle.setView('dashboard');
assert.equal(lifecycle.current(newerRpcRender), false, 'leaving the task workspace invalidates its pending result');

const renderGuard = app.indexOf('if (!isCurrentTaskDirectoryLoad(taskDirectoryContext)) return null;', app.indexOf('async function renderTasks()'));
const supervisorCacheWrite = app.indexOf('window.taskDepartmentSupervisors = departmentSupervisors || [];', renderGuard);
const employeeCacheWrite = app.indexOf('window.taskAllUsersCache = allUsers;', renderGuard);
const departmentCacheWrite = app.indexOf('window.taskDepartmentsCache = allDepartments;', renderGuard);
assert.ok(renderGuard !== -1 && supervisorCacheWrite > renderGuard && employeeCacheWrite > renderGuard && departmentCacheWrite > renderGuard,
    'all async task-directory results are checked before shared caches are written');
assert.match(app, /updateTaskDirectoryAuthIdentity\(session\?\.user\?\.id \|\| null, !session \|\| event === 'SIGNED_OUT'\)/,
    'auth identity changes and sign-out invalidate pending loads');
assert.match(app, /if \(!isCurrentTaskDirectoryLoad\(taskDirectoryContext\)\) return null;\s+window\.taskV2HealthFilter/,
    'stale renders are rejected before task UI construction');
assert.match(app, /if \(content === null\) return;/, 'background rendering does not paint stale task content');
assert.match(app, /content = await renderTasksV2\(\);\s+if \(content === null\) return;/,
    'stale task renders are not installed by navigation rendering');

const deferred = () => {
    let resolve;
    const promise = new Promise(done => { resolve = done; });
    return { promise, resolve };
};
const applyAfterLoad = async (context, promise, cacheName) => {
    const value = await promise;
    if (!lifecycle.current(context)) return false;
    lifecycleSandbox.window[cacheName] = value;
    return true;
};

(async () => {
    lifecycle.auth('user-a');
    lifecycle.setUser('user-a');
    lifecycle.setView('tasks');
    const olderResponse = deferred();
    const olderContext = lifecycle.begin();
    const olderApply = applyAfterLoad(olderContext, olderResponse.promise, 'taskAllUsersCache');
    const newerContext = lifecycle.begin();
    assert.equal(await applyAfterLoad(newerContext, Promise.resolve([{ id: 'new-user' }]), 'taskAllUsersCache'), true);
    olderResponse.resolve([{ id: 'old-user' }]);
    assert.equal(await olderApply, false, 'older request finishing after a newer render cannot replace current caches');
    assert.equal(lifecycleSandbox.window.taskAllUsersCache[0].id, 'new-user');

    const departmentResponse = deferred();
    const profileResponse = deferred();
    const signingOutContext = lifecycle.begin();
    const departmentApply = applyAfterLoad(signingOutContext, departmentResponse.promise, 'taskDepartmentsCache');
    const profileApply = applyAfterLoad(signingOutContext, profileResponse.promise, 'taskAllUsersCache');
    lifecycle.auth(null, true);
    lifecycle.setUser(null);
    departmentResponse.resolve([{ id: 'private-dept' }]);
    profileResponse.resolve([{ id: 'private-profile' }]);
    assert.equal(await departmentApply, false, 'late department response after sign-out is rejected');
    assert.equal(await profileApply, false, 'late profile response after sign-out is rejected');
    assert.equal(lifecycleSandbox.window.taskDepartmentsCache.length, 0);
    assert.equal(lifecycleSandbox.window.taskAllUsersCache.length, 0);

    lifecycle.auth('user-a');
    lifecycle.setUser('user-a');
    const userAResponse = deferred();
    const userAContext = lifecycle.begin();
    const userAApply = applyAfterLoad(userAContext, userAResponse.promise, 'taskDepartmentSupervisors');
    lifecycle.auth('user-b');
    lifecycle.setUser('user-b');
    const userBContext = lifecycle.begin();
    assert.equal(await applyAfterLoad(userBContext, Promise.resolve([{ id: 'user-b-manager' }]), 'taskDepartmentSupervisors'), true);
    userAResponse.resolve([{ id: 'user-a-manager' }]);
    assert.equal(await userAApply, false, 'late caller-scoped supervisor result cannot cross authenticated users');
    assert.equal(lifecycleSandbox.window.taskDepartmentSupervisors[0].id, 'user-b-manager');

    console.log('Task department manager display, identifier normalization, async session isolation, status, and caller-scope checks passed.');
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
