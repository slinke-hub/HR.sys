const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261118190000_admin_page_feature_access_controls.sql'), 'utf8');

function assert(condition, message) {
    if (!condition) throw new Error(message);
}

assert(migration.includes('disabled_features JSONB') && migration.includes('disabled_pages JSONB'), 'migration adds page and feature disable storage');
assert(migration.includes('SYSTEM ADMINISTRATOR'), 'migration recognizes the administrator role');
assert(db.includes('disabled_features: disabledFeatures'), 'database writes disabled features');
assert(db.includes('disabledFeatures: data.disabled_features'), 'database reads disabled features');
assert(db.includes('disabled_pages: disabledPages'), 'database writes disabled pages');
assert(db.includes('disabledPages: data.disabled_pages'), 'database reads disabled pages');
assert(app.includes('APP_FEATURE_CATALOG'), 'application defines a stable feature catalog');
assert(app.includes('canCurrentUserUseFeature'), 'application evaluates feature access');
assert(app.includes('canCurrentUserAccessPageOverride'), 'application evaluates explicit page disables');
assert(app.includes('handleGrantFeature'), 'admin UI can disable a feature');
assert(app.includes('toggleUserFeature') && app.includes('toggleRoleFeature'), 'admin UI can scope feature controls');
assert(app.includes('admin_page_access') && app.includes('project-command-center'), 'admin page catalog includes full application routes');
assert(app.includes("requireFeature('task_create')") && app.includes("requireFeature('crm_stage_change')"), 'critical task and CRM actions enforce feature access');
console.log('admin-access-control: PASS');
