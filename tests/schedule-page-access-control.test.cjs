/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const app = read('js/app.js');
const html = read('index.html');
const data = read('js/data.js');
const db = read('js/db.js');

const userPermissionMethodStart = db.indexOf('async fetchUserPermissions(userId)');
const userPermissionMethodEnd = db.indexOf('async fetchAllUserPermissions()', userPermissionMethodStart);
assert.ok(userPermissionMethodStart >= 0 && userPermissionMethodEnd > userPermissionMethodStart, 'User-permission helper boundaries exist');
const userPermissionMethodSource = db.slice(userPermissionMethodStart, userPermissionMethodEnd)
    .trim()
    .replace(/^async fetchUserPermissions/, 'async function fetchUserPermissions')
    .replace(/},\s*$/, '}');

function productionUserPermissionFetcher(result, hasClient = true) {
    const context = {
        supabaseClient: hasClient ? {
            from: () => ({
                select: () => ({
                    eq: () => ({ maybeSingle: async () => result })
                })
            })
        } : null,
        console: { error: () => {} }
    };
    vm.runInNewContext(`${userPermissionMethodSource}\nthis.fetchUserPermissions = fetchUserPermissions;`, context);
    return context.fetchUserPermissions;
}

const accessStart = app.indexOf('async function canCurrentUserAccessView(viewId)');
const accessEnd = app.indexOf('window.ensureCurrentScheduleAccess = async function', accessStart);
const accessSource = app.slice(accessStart, accessEnd);
const explicitViewsDeclaration = app.match(/const EXPLICIT_PAGE_ACCESS_VIEWS = new Set\(\['schedule'\]\);/)?.[0];
assert.ok(explicitViewsDeclaration, 'Schedule is registered as an explicit-grant page');

async function evaluateScheduleAccess({
    role = 'EMPLOYEE',
    userPages = [],
    rolePermissions = [{ role: 'EMPLOYEE', allowed_pages: ['dashboard'] }],
    departmentId = 'dept-1',
    ready = true,
    failed = false,
    permissionsUserId = 'user-1',
    currentUserId = 'user-1',
    backendAllowed = null
} = {}) {
    const normalizedRole = String(role || '').toUpperCase();
    const effectiveBackendAllowed = backendAllowed ?? (
        ['ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'].includes(normalizedRole)
        || userPages.includes('schedule')
        || rolePermissions.some(permission => permission.role === normalizedRole && permission.allowed_pages?.includes('schedule'))
        || rolePermissions.some(permission => permission.role === `DEPT_${departmentId}` && permission.allowed_pages?.includes('schedule'))
    );
    const context = {
        window: {
            appUserPermissions: userPages,
            appRolePermissionsCache: rolePermissions,
            appPagePermissionsReady: ready,
            appPagePermissionsFailed: failed,
            appPagePermissionsUserId: permissionsUserId,
            location: { search: '' },
            canCurrentUserUseHrSuiteBeta: () => false,
            verifyCurrentSchedulePageAccess: async () => effectiveBackendAllowed
        },
        currentUserRole: role,
        currentUserProfile: { role, department_id: departmentId, job_title: '' },
        currentUser: { id: currentUserId, department_id: departmentId },
        isAdminRole: value => ['ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'].includes(String(value || '').toUpperCase()),
        canViewFullProjectCommandCenter: () => false,
        canCurrentUserManageUsers: () => false,
        canCurrentUserUseCRM: () => false,
        getCurrentDepartmentName: async () => '',
        hasAccessibleProjectMembership: async () => false,
        db: {},
        URLSearchParams
    };
    vm.runInNewContext(`${explicitViewsDeclaration}\n${accessSource}\nthis.checkPageAccess = canCurrentUserAccessView;`, context);
    return context.checkPageAccess('schedule');
}

(async () => {
    const noIndividualRecordFetcher = productionUserPermissionFetcher({ data: null, error: null });
    assert.equal(await noIndividualRecordFetcher('user-1'), null, 'A successful query with no individual row remains distinguishable from failure');
    const individualPages = ['schedule'];
    const individualRecordFetcher = productionUserPermissionFetcher({ data: { allowed_pages: individualPages }, error: null });
    assert.deepEqual(await individualRecordFetcher('user-1'), individualPages, 'A successful individual permission row is returned unchanged');
    const individualQueryError = new Error('individual permission query failed');
    const failedIndividualFetcher = productionUserPermissionFetcher({ data: null, error: individualQueryError });
    await assert.rejects(failedIndividualFetcher('user-1'), error => error === individualQueryError, 'Production helper rethrows the original individual query error');
    await assert.rejects(productionUserPermissionFetcher(null, false)('user-1'), /Supabase client is unavailable/, 'Missing database client is a detectable permission-load failure');

    for (const role of ['ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN']) {
        assert.equal(await evaluateScheduleAccess({ role, ready: false, failed: true, rolePermissions: [] }), true, `${role} retains the administrator bypass`);
    }

    for (const role of ['EMPLOYEE', 'MANAGER', 'SUPERVISOR', 'HR_MANAGER']) {
        assert.equal(await evaluateScheduleAccess({ role, rolePermissions: [{ role, allowed_pages: ['dashboard'] }] }), false, `${role} is denied without an explicit Schedule grant`);
        assert.equal(await evaluateScheduleAccess({ role, rolePermissions: [{ role, allowed_pages: ['schedule'] }] }), true, `${role} can receive a role Schedule grant`);
    }

    assert.equal(await evaluateScheduleAccess({ userPages: ['schedule'] }), true, 'Individual Schedule grants are honored');
    assert.equal(await evaluateScheduleAccess({ rolePermissions: [{ role: 'DEPT_dept-1', allowed_pages: ['schedule'] }] }), true, 'Department Schedule grants are honored');
    assert.equal(await evaluateScheduleAccess({ userPages: [], rolePermissions: [{ role: 'EMPLOYEE', allowed_pages: ['dashboard'] }] }), false, 'An explicit empty individual allow-list does not grant Schedule');
    assert.equal(await evaluateScheduleAccess({ userPages: [], rolePermissions: [{ role: 'EMPLOYEE', allowed_pages: ['schedule'] }] }), true, 'Existing additive precedence preserves a valid role grant when the individual list is empty');
    assert.equal(await evaluateScheduleAccess({ userPages: ['schedule'], ready: false }), false, 'Schedule fails closed while permission data is loading');
    assert.equal(await evaluateScheduleAccess({ userPages: ['schedule'], failed: true }), false, 'Schedule fails closed when permission retrieval fails');
    assert.equal(await evaluateScheduleAccess({ userPages: ['schedule'], permissionsUserId: 'another-user' }), false, 'Permissions cached for another user cannot authorize Schedule');
    assert.equal(await evaluateScheduleAccess({ userPages: ['schedule'], backendAllowed: false }), false, 'Forged client-side grants cannot override the authoritative backend denial');
    assert.equal(await evaluateScheduleAccess({ role: 'ADMIN', backendAllowed: false }), false, 'Administrator access also fails closed when backend verification fails');

    const evaluatorContext = {
        window: { appUserPermissions: [], appRolePermissionsCache: [], appPagePermissionsReady: true, appPagePermissionsFailed: false, appPagePermissionsUserId: 'user-1', location: { search: '' }, canCurrentUserUseHrSuiteBeta: () => false, verifyCurrentSchedulePageAccess: async () => false },
        currentUserRole: 'MANAGER', currentUserProfile: { role: 'MANAGER' }, currentUser: { id: 'user-1' },
        isAdminRole: () => false, canViewFullProjectCommandCenter: () => false, canCurrentUserManageUsers: () => false,
        canCurrentUserUseCRM: () => false, getCurrentDepartmentName: async () => '', hasAccessibleProjectMembership: async () => false,
        db: {}, URLSearchParams
    };
    vm.runInNewContext(`${explicitViewsDeclaration}\n${accessSource}\nthis.checkPageAccess = canCurrentUserAccessView;`, evaluatorContext);
    assert.equal(await evaluatorContext.checkPageAccess('dashboard'), true, 'Legacy fallback remains unchanged for unrelated manager pages');

    const pageAccessSource = app.slice(app.indexOf('async function renderAdminPageAccess()'), app.indexOf('// Render User Management (Admin Only)'));
    assert.match(pageAccessSource, /id: 'schedule', label: t\('nav_schedule'\), icon: 'calendar-clock', group: 'workforce'/, 'Schedule appears in Pages Access Controls');
    assert.match(pageAccessSource, /window\.adminPageAccessDataReady = false/, 'Administration starts with permission mutations disabled');
    assert.match(pageAccessSource, /catch \(error\)[\s\S]*?Permission data could not be loaded[\s\S]*?Retry/, 'Administration shows a hard load error instead of an empty permission set');
    assert.match(pageAccessSource, /window\.adminPageAccessDataReady = true/, 'Administration enables mutations only after every permission source loads');
    assert.ok((pageAccessSource.match(/window\.adminPageAccessDataReady !== true/g) || []).length >= 5, 'All grant and revoke entry points reject incomplete permission data');
    assert.match(db.slice(db.indexOf('async fetchAllRolePermissions()'), db.indexOf('async updateRolePermissions')), /catch \(error\)[\s\S]*?throw error/, 'Role-permission administration query failures propagate');
    assert.match(db.slice(db.indexOf('async fetchAllUserPermissions()'), db.indexOf('async fetchEffectivePageAccess')), /catch \(error\)[\s\S]*?throw error/, 'Employee-permission administration query failures propagate');
    assert.match(data, /nav_schedule: "Schedule & Reminders"/, 'Existing English label is reused');
    assert.match(data, /nav_schedule: "الجدول والتذكيرات"/, 'Existing Arabic label is reused');

    const permissionLoaderSource = app.slice(app.indexOf('window.loadPageAccessPermissions = async function'), accessStart);
    assert.match(permissionLoaderSource, /window\.resetPageAccessPermissions\(\)/);
    assert.match(permissionLoaderSource, /Promise\.all\(\[\s*window\.loadRolePermissions\(\),\s*window\.loadUserPermissions\(userId\)/);
    assert.match(permissionLoaderSource, /appPagePermissionsFailed = !rolePermissionsLoaded \|\| !userPermissionsLoaded \|\| !sameUser/);
    assert.equal((app.match(/db\.fetchUserPermissions\(userId\)/g) || []).length, 1, 'User-permission helper has one audited application caller');
    const userPermissionCallerSource = app.slice(app.indexOf('window.loadUserPermissions = async function'), app.indexOf('window.loadPageAccessPermissions = async function'));
    assert.match(userPermissionCallerSource, /catch \(e\)[\s\S]*?appUserPermissions = \[\][\s\S]*?return false/, 'The caller converts propagated database errors into a failed permission load');
    assert.match(userPermissionMethodSource, /catch \(error\)[\s\S]*?throw error/, 'Production helper propagates the original query error');
    assert.match(db, /rpc\('has_my_page_access', \{ p_page: pageId \}\)/, 'Schedule permission is verified by the authenticated-user backend RPC');

    const scheduleVerificationSource = app.slice(app.indexOf('window.verifyCurrentSchedulePageAccess = async function'), accessStart);
    assert.match(scheduleVerificationSource, /requestId !== Number\(window\.schedulePageAccessVerification\?\.requestId \|\| 0\)/, 'Stale Schedule authorization responses are rejected');
    assert.match(scheduleVerificationSource, /userId !== String\(currentUser\?\.id \|\| ''\)/, 'Schedule authorization results cannot cross user sessions');
    assert.match(scheduleVerificationSource, /result\?\.success === true && result\?\.allowed === true/, 'Backend errors and non-true responses fail closed');

    const allPermissionLoaderSource = app.slice(app.indexOf('window.appRolePermissionsCache = []'), accessStart);
    async function runPermissionLoader(fetchAllRolePermissions, fetchUserPermissions) {
        const context = {
            window: {},
            currentUser: { id: 'user-1' },
            db: { fetchAllRolePermissions, fetchUserPermissions },
            console: { error: () => {} }
        };
        vm.runInNewContext(allPermissionLoaderSource, context);
        const success = await context.window.loadPageAccessPermissions('user-1');
        return { success, state: context.window };
    }

    const successfulLoader = await runPermissionLoader(
        async () => [{ role: 'EMPLOYEE', allowed_pages: ['dashboard'] }],
        noIndividualRecordFetcher
    );
    assert.equal(successfulLoader.success, true, 'Permission loader accepts a successful query with no individual row');
    assert.equal(successfulLoader.state.appPagePermissionsReady, true);
    assert.equal(successfulLoader.state.appPagePermissionsFailed, false);

    const failedIndividualLoader = await runPermissionLoader(
        async () => [{ role: 'EMPLOYEE', allowed_pages: ['dashboard'] }],
        failedIndividualFetcher
    );
    assert.equal(failedIndividualLoader.success, false, 'Individual permission query failure fails the combined load');
    assert.equal(failedIndividualLoader.state.appPagePermissionsFailed, true);

    const failedRoleLoader = await runPermissionLoader(
        async () => { throw new Error('role permission query failed'); },
        noIndividualRecordFetcher
    );
    assert.equal(failedRoleLoader.success, false, 'Role permission query failure fails the combined load');
    assert.equal(failedRoleLoader.state.appPagePermissionsFailed, true);

    const roleGrantWithIndividualFailure = await runPermissionLoader(
        async () => [{ role: 'MANAGER', allowed_pages: ['schedule'] }],
        failedIndividualFetcher
    );
    assert.equal(roleGrantWithIndividualFailure.success, false);
    assert.equal(await evaluateScheduleAccess({ role: 'MANAGER', rolePermissions: roleGrantWithIndividualFailure.state.appRolePermissionsCache, failed: roleGrantWithIndividualFailure.state.appPagePermissionsFailed }), false, 'Role grant cannot override an individual query failure');

    const departmentGrantWithIndividualFailure = await runPermissionLoader(
        async () => [{ role: 'DEPT_dept-1', allowed_pages: ['schedule'] }],
        failedIndividualFetcher
    );
    assert.equal(departmentGrantWithIndividualFailure.success, false);
    assert.equal(await evaluateScheduleAccess({ rolePermissions: departmentGrantWithIndividualFailure.state.appRolePermissionsCache, failed: departmentGrantWithIndividualFailure.state.appPagePermissionsFailed }), false, 'Department grant cannot override an individual query failure');

    const failedDepartmentSource = await runPermissionLoader(
        async () => { throw new Error('department permission source failed'); },
        noIndividualRecordFetcher
    );
    assert.equal(failedDepartmentSource.success, false, 'Department grants fail closed when their shared role-permission source fails');
    assert.equal(await evaluateScheduleAccess({ rolePermissions: [{ role: 'DEPT_dept-1', allowed_pages: ['schedule'] }], failed: failedDepartmentSource.state.appPagePermissionsFailed }), false, 'Unresolved department permissions cannot authorize Schedule');

    const sidebarSource = app.slice(app.indexOf('window.updateSidebarVisibility = async function'), app.indexOf('window.handleLoginSubmit = async function'));
    assert.match(sidebarSource, /const canAccessSchedule = await canCurrentUserAccessView\('schedule'\)/, 'Desktop navigation uses the central Schedule evaluator');
    assert.match(sidebarSource, /viewId === 'schedule'[\s\S]*?canAccessSchedule \? 'flex' : 'none'/);
    assert.match(html, /data-view="schedule" style="display:none"/, 'Protected navigation starts hidden');

    const mobileStart = app.indexOf('window.openMobileNavigation = async function');
    const mobileSource = app.slice(mobileStart, app.indexOf('window.updateNavigationControlLabels = function', mobileStart));
    assert.match(mobileSource, /canCurrentUserAccessView\(item\.dataset\.view\)/, 'Mobile navigation reuses the central evaluator');

    const loginSource = app.slice(app.indexOf('window.handleLoginSubmit = async function'), app.indexOf('// Render Login View'));
    assert.ok(loginSource.indexOf('await window.loadPageAccessPermissions(user.id)') < loginSource.indexOf("document.querySelector('.sidebar').style.display = ''"), 'Fresh login loads permissions before showing navigation');
    assert.match(loginSource, /await window\.updateSidebarVisibility\(\)/);

    const initSource = app.slice(app.indexOf('async function initApp()'));
    const restoredSessionStart = initSource.indexOf('if (session && session.user)');
    const restoredSessionSource = initSource.slice(restoredSessionStart, initSource.indexOf('const restorableViews', restoredSessionStart));
    assert.ok(restoredSessionSource.indexOf('await window.loadPageAccessPermissions(currentUser.id)') < restoredSessionSource.indexOf("document.querySelector('.sidebar').style.display = ''"), 'Restored sessions load permissions before showing navigation');
    assert.match(initSource, /window\.resetPageAccessPermissions\(\)[\s\S]*?currentUser = null/, 'Sign-out clears cached page grants');
    const logoutStart = app.indexOf('window.handleLogout = async function');
    const logoutSource = app.slice(logoutStart, app.indexOf('// Profile dropdown', logoutStart));
    assert.match(logoutSource, /window\.resetPageAccessPermissions\(\)/, 'Manual logout immediately clears cached page grants');

    const renderViewStart = app.indexOf('window.renderView = async function');
    const renderViewSource = app.slice(renderViewStart, app.indexOf('// Init', renderViewStart));
    assert.match(renderViewSource, /if \(currentUser && viewId !== 'login' && !\(await canCurrentUserAccessView\(viewId\)\)\)/, 'Direct renderView navigation is guarded');
    assert.match(renderViewSource, /case 'schedule': content = await renderSchedule\(\)/, 'Authorized Schedule routing is preserved');
    assert.match(app, /window\.addEventListener\('popstate'[\s\S]*?void renderView\(previousView, true\)/, 'Browser history returns through renderView');
    assert.match(initSource, /restoredNav\.style\.display === 'none'\) currentView = 'dashboard'/, 'Unauthorized saved views fall back to Dashboard');

    const resumeAccessSource = app.slice(app.indexOf('let scheduleAccessResumeCheckInFlight'), app.indexOf('async function hasAccessibleProjectMembership'));
    assert.match(resumeAccessSource, /window\.loadPageAccessPermissions\(currentUser\.id\)/, 'Returning to an open Schedule view reloads authoritative permission sources');
    assert.match(resumeAccessSource, /window\.ensureCurrentScheduleAccess\(\)/, 'Returning to an open Schedule view rechecks backend access');
    assert.match(resumeAccessSource, /window\.addEventListener\('focus'/, 'Window focus triggers Schedule revocation detection');
    assert.match(resumeAccessSource, /document\.addEventListener\('visibilitychange'/, 'Visibility restoration triggers Schedule revocation detection');

    const scheduleStart = app.indexOf('async function renderSchedule()');
    const scheduleEnd = app.indexOf('async function renderProfile()', scheduleStart);
    assert.ok(scheduleStart >= 0 && scheduleEnd > scheduleStart, 'Reminder implementation has verified function boundaries');
    const scheduleSource = app.slice(scheduleStart, scheduleEnd);
    const assertReminderContract = source => {
        assert.match(source, /db\.fetchReminders\(currentUser\.id\)/, 'Reminder renderer fetches personal reminders');
        assert.match(source, /db\.createReminder\(/, 'Reminder creation remains wired');
        assert.match(source, /db\.updateReminderStatus\(/, 'Reminder status updates remain wired');
        assert.match(source, /db\.deleteReminder\(/, 'Reminder deletion remains wired');
        assert.match(source, /calendar\.google\.com\/calendar\/render/, 'Google Calendar integration remains wired');
        assert.match(source, /window\.enablePushNotifications/, 'Reminder notifications remain wired');
    };
    assertReminderContract(scheduleSource);
    assert.match(scheduleSource, /window\.ensureCurrentScheduleAccess\(\)/, 'Reminder create, update, and delete actions require a fresh Schedule access check');
    assert.ok((scheduleSource.match(/window\.ensureCurrentScheduleAccess\(\)/g) || []).length >= 5, 'All reminder mutation and notification entry points are guarded');
    assert.throws(
        () => assertReminderContract(scheduleSource.replace('db.fetchReminders(currentUser.id)', 'db.fetchSomethingElse(currentUser.id)')),
        /Reminder renderer fetches personal reminders/,
        'Reminder contract test detects an unexpected implementation change'
    );
    assert.match(db, /async fetchReminders\(userId\)/);
    assert.match(db, /async createReminder\(reminderData\)/);
    assert.match(db, /async updateReminderStatus\(id, status\)/);
    assert.match(db, /async deleteReminder\(id\)/);

    assert.match(app, /dir="\$\{currentLang === 'ar' \? 'rtl' : 'ltr'\}"/, 'Mobile navigation preserves RTL/LTR direction');
    console.log('Schedule page access-control checks passed.');
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
