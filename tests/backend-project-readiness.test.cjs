/* Static contract checks for authoritative Project services. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260917130000_project_backend_services.sql'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js/db.js'), 'utf8');
const bridge = fs.readFileSync(path.join(root, 'js/shared-services.js'), 'utf8');
const contracts = fs.readFileSync(path.join(root, 'src/shared/domain-services.ts'), 'utf8');

for (const fn of ['create_project_secure', 'update_project_secure', 'delete_project_secure', 'list_project_updates_secure', 'list_project_todos_secure', 'get_project_detail_secure']) {
  assert.match(migration, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}`));
  assert.match(migration, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}`));
  assert.match(migration, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}`));
}
assert.match(migration, /REVOKE ALL ON public\.projects FROM authenticated/);
assert.match(migration, /REVOKE ALL ON public\.project_updates FROM authenticated/);
assert.match(migration, /REVOKE ALL ON public\.project_todos FROM authenticated/);
assert.match(migration, /can_view_business_financials/);
assert.match(migration, /can_access_project/);
assert.match(migration, /jsonb_populate_record/);
assert.match(db, /rpc\('create_project_secure'/);
assert.match(db, /rpc\('update_project_secure'/);
assert.match(db, /rpc\('delete_project_secure'/);
assert.match(db, /rpc\('get_project_detail_secure'/);
assert.match(db, /rpc\('list_project_updates_secure'/);
assert.match(db, /rpc\('list_project_todos_secure'/);
assert.doesNotMatch(db.slice(db.indexOf('async createProject(projectData)'), db.indexOf('async fetchProjectSharedAttachments')), /\.from\('projects'\)\s*\.insert|\.from\('projects'\)\s*\.update|\.from\('projects'\)\s*\.delete/);
assert.doesNotMatch(db.slice(db.indexOf('async fetchProjectUpdates'), db.indexOf('async createProjectUpdateSecure')), /\.from\('project_updates'\)/);
assert.doesNotMatch(db.slice(db.indexOf('async fetchProjectTodos'), db.indexOf('async addProjectTodo')), /\.from\('project_todos'\)/);
assert.match(bridge, /details: id => db\.fetchProjectDetails/);
assert.match(bridge, /create: payload => db\.createProject/);
assert.match(contracts, /fetchProjectDetails/);
assert.match(contracts, /create: \(payload/);
console.log('Project backend authoritative service checks passed.');
