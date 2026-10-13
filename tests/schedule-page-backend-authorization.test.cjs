/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const migration = read('supabase/migrations/20261013100000_schedule_page_backend_authorization.sql');
const dispatcher = read('supabase/functions/push-notification-dispatcher/index.ts');
const app = read('js/app.js');
const db = read('js/db.js');

const compact = value => String(value || '').trim().toUpperCase().replace(/[_-]+/g, ' ').replace(/\s+/g, ' ');
const adminRoles = new Set(['ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN']);
const executiveTitles = new Set(['GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER']);
function simulatedEffectiveAccess({ authenticated = true, active = true, role = 'EMPLOYEE', jobTitle = '', jobTitleAr = '', individual = [], rolePages = [], departmentPages = [] } = {}) {
    if (!authenticated || !active) return false;
    const normalizedRole = compact(role);
    const normalizedTitle = compact(jobTitle);
    const executive = executiveTitles.has(normalizedTitle)
        || /^(GENERAL MANAGER|CHIEF EXECUTIVE OFFICER) \((GM|CEO)\)$/.test(normalizedTitle)
        || ['المدير العام', 'الرئيس التنفيذي'].includes(String(jobTitleAr || '').trim());
    return adminRoles.has(normalizedRole)
        || executive
        || individual.includes('schedule')
        || rolePages.includes('schedule')
        || departmentPages.includes('schedule');
}

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.has_effective_page_access_internal\(\s*p_user_id uuid,\s*p_page text\s*\)/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.has_my_page_access\(p_page text\)/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.list_due_schedule_reminders_for_dispatch\(p_limit integer DEFAULT 100\)/);
assert.equal((migration.match(/SECURITY DEFINER/g) || []).length, 3, 'All trusted authorization functions use explicit definer execution');
assert.equal((migration.match(/SET search_path TO public, pg_temp/g) || []).length, 3, 'All definer functions pin a safe search path');

assert.match(migration, /has_my_page_access[\s\S]*?auth\.uid\(\)[\s\S]*?has_effective_page_access_internal\(auth\.uid\(\), p_page\)/, 'Authenticated evaluator derives identity only from auth.uid()');
assert.match(migration, /profile\.is_active IS DISTINCT FROM false/, 'Inactive profiles are denied');
assert.match(migration, /FROM public\.user_permissions[\s\S]*?individual_permission\.user_id = p_user_id[\s\S]*?allowed_pages \? normalized_page/, 'Individual grants are authoritative');
assert.match(migration, /FROM public\.role_permissions[\s\S]*?role_permission\.role = UPPER\(BTRIM\(COALESCE\(profile_role, ''\)\)\)[\s\S]*?allowed_pages \? normalized_page/, 'Role grants are authoritative');
assert.match(migration, /department_permission\.role = 'DEPT_' \|\| profile_department_id::text[\s\S]*?allowed_pages \? normalized_page/, 'Synthetic department grants are authoritative');
assert.match(migration, /'ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN'/, 'Administrative roles are preserved');
assert.match(migration, /'GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER'/, 'Approved executive administrator titles are preserved');
assert.match(migration, /'المدير العام', 'الرئيس التنفيذي'/, 'Approved Arabic executive titles are preserved');
assert.equal((migration.match(/EXCEPTION WHEN OTHERS THEN/g) || []).length, 2, 'Authorization evaluators fail closed on lookup errors');

assert.match(migration, /REVOKE ALL ON FUNCTION public\.has_effective_page_access_internal\(uuid, text\) FROM PUBLIC, anon, authenticated;/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.has_effective_page_access_internal\(uuid, text\) TO service_role;/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.has_my_page_access\(text\) FROM PUBLIC, anon(?:, authenticated)?;/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.has_my_page_access\(text\) TO authenticated;/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.list_due_schedule_reminders_for_dispatch\(integer\) FROM PUBLIC, anon, authenticated;/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.list_due_schedule_reminders_for_dispatch\(integer\) TO service_role;/);

for (const operation of ['SELECT', 'INSERT', 'UPDATE', 'DELETE']) {
    assert.match(migration, new RegExp(`CREATE POLICY "Users can \\w+ their reminders"[\\s\\S]*?FOR ${operation} TO authenticated`), `${operation} reminder policy is replaced`);
}
assert.equal((migration.match(/user_id = auth\.uid\(\)/g) || []).length, 5, 'Every reminder policy clause preserves ownership');
assert.equal((migration.match(/public\.has_my_page_access\('schedule'\)/g) || []).length, 5, 'Every reminder policy clause requires Schedule permission');
const updatePolicy = migration.slice(migration.indexOf('CREATE POLICY "Users can update their reminders"'), migration.indexOf('DROP POLICY IF EXISTS "Users can delete their reminders"'));
assert.match(updatePolicy, /USING\s*\([\s\S]*?user_id = auth\.uid\(\)[\s\S]*?has_my_page_access\('schedule'\)[\s\S]*?\)/);
assert.match(updatePolicy, /WITH CHECK\s*\([\s\S]*?user_id = auth\.uid\(\)[\s\S]*?has_my_page_access\('schedule'\)[\s\S]*?\)/);
assert.doesNotMatch(migration, /INSERT INTO public\.(?:user_permissions|role_permissions|reminders)/i, 'Migration does not auto-grant or alter historical reminders');
assert.doesNotMatch(migration, /UPDATE public\.(?:user_permissions|role_permissions|reminders)/i, 'Migration contains no permission or reminder data rewrite');

assert.match(migration, /reminder\.status = 'pending'[\s\S]*?reminder\.due_date <= now\(\)[\s\S]*?reminder\.last_notified_at IS NULL/, 'Due reminder semantics are preserved');
assert.match(migration, /has_effective_page_access_internal\(reminder\.user_id, 'schedule'\)/, 'Dispatcher list is authorization filtered');
assert.match(migration, /LIMIT LEAST\(GREATEST\(COALESCE\(p_limit, 100\), 1\), 500\)/, 'Privileged list is bounded');

assert.match(dispatcher, /rpc\("list_due_schedule_reminders_for_dispatch", \{ p_limit: 100 \}\)/, 'Dispatcher uses the filtered due-reminder RPC');
assert.doesNotMatch(dispatcher, /from\("reminders"\)\s*\n\s*\.select/, 'Dispatcher no longer performs an unrestricted service-role reminder read');
assert.ok((dispatcher.match(/hasScheduleAccess\(reminder\.user_id\)/g) || []).length >= 2, 'Dispatcher revalidates before delivery and before update');
assert.match(dispatcher, /\.eq\("id", reminder\.id\)\.eq\("user_id", reminder\.user_id\)/, 'Privileged reminder updates remain owner scoped');
assert.match(dispatcher, /nextOccurrence\(reminder\.due_date, reminder\.recurrence_type, reminder\.recurrence_interval\)/, 'Recurrence behavior is preserved');
assert.match(dispatcher, /last_notified_at: null/, 'Recurring reminder notification reset is preserved');
assert.match(dispatcher, /from\("notifications"\)[\s\S]*?push_sent_at/, 'Unrelated application notifications remain in the dispatcher');
assert.match(dispatcher, /from\("push_subscriptions"\)/, 'Existing push subscriptions remain in use');
assert.match(dispatcher, /PUSH_DISPATCH_SECRET/, 'Dispatch-secret validation remains present');

assert.match(db, /rpc\('has_my_page_access', \{ p_page: pageId \}\)/, 'Web access checks use the authenticated database evaluator');
assert.match(app, /result\?\.success === true && result\?\.allowed === true/, 'Web authorization fails closed on RPC errors');
assert.match(app, /requestId !== Number\(window\.schedulePageAccessVerification\?\.requestId \|\| 0\)/, 'Stale web authorization responses are ignored');
assert.match(app, /userId !== String\(currentUser\?\.id \|\| ''\)/, 'Web authorization responses are session-bound');

for (const role of ['ADMIN', 'OWNER', 'ROLE SYSTEM ADMIN', 'SYSTEM ADMIN']) {
    assert.equal(simulatedEffectiveAccess({ role }), true, `${role} is locally simulated as an administrator`);
}
for (const jobTitle of ['GM', 'GENERAL MANAGER', 'CEO', 'CHIEF EXECUTIVE', 'CHIEF EXECUTIVE OFFICER', 'GENERAL MANAGER (GM)', 'CHIEF EXECUTIVE OFFICER (CEO)']) {
    assert.equal(simulatedEffectiveAccess({ jobTitle }), true, `${jobTitle} is locally simulated as an executive administrator`);
}
assert.equal(simulatedEffectiveAccess({ jobTitleAr: 'المدير العام' }), true);
assert.equal(simulatedEffectiveAccess({ jobTitleAr: 'الرئيس التنفيذي' }), true);
assert.equal(simulatedEffectiveAccess({ individual: ['schedule'] }), true, 'Individual grant authorizes');
assert.equal(simulatedEffectiveAccess({ rolePages: ['schedule'] }), true, 'Role grant authorizes');
assert.equal(simulatedEffectiveAccess({ departmentPages: ['schedule'] }), true, 'Department grant authorizes');
assert.equal(simulatedEffectiveAccess({ individual: [], rolePages: ['schedule'] }), true, 'Empty individual grants do not override role grants');
assert.equal(simulatedEffectiveAccess({ individual: [], departmentPages: ['schedule'] }), true, 'Empty individual grants do not override department grants');
assert.equal(simulatedEffectiveAccess(), false, 'No grant denies');
assert.equal(simulatedEffectiveAccess({ authenticated: false, role: 'ADMIN' }), false, 'Anonymous access denies');
assert.equal(simulatedEffectiveAccess({ active: false, role: 'ADMIN' }), false, 'Inactive profiles deny');
assert.equal(false && simulatedEffectiveAccess({ individual: ['schedule'] }), false, 'Cross-employee ownership remains denied even for an authorized caller');

console.log('Schedule backend authorization static and local simulation checks passed (no database was contacted).');
