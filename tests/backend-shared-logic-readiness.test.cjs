/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

const migration = read('supabase/migrations/20260917090000_shared_business_logic_services.sql');
const db = read('js/db.js');
const app = read('js/app.js');
const index = read('index.html');
const sharedTypes = read('src/shared/domain-types.ts');
const sharedServices = read('src/shared/domain-services.ts');
const browserBridge = read('js/shared-services.js');
const fileContracts = read('src/shared/file-contracts.ts');
const authContract = read('src/shared/auth-contract.ts');
const notificationContract = read('src/shared/notification-contract.ts');

for (const fn of ['change_crm_deal_stage', 'mark_crm_deal_lost', 'change_task_status', 'assign_task', 'change_project_status', 'assign_project_team', 'create_project_update_secure', 'start_deal_approval', 'finalize_crm_deal_approval']) {
  assert.match(migration, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}`));
  assert.match(migration, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}`));
}
assert.match(migration, /REVOKE ALL ON FUNCTION public\.change_crm_deal_stage\(uuid, text\) FROM PUBLIC, anon/);
assert.match(migration, /INSERT INTO public\.crm_deal_activity/);
assert.match(migration, /validate_shared_attachment_metadata/);
assert.match(migration, /Attachment exceeds the 25 MB limit/);
assert.match(migration, /UPDATE public\.tasks SET status = v_status/);
assert.match(db, /rpc\('change_crm_deal_stage'/);
assert.match(db, /rpc\('mark_crm_deal_lost'/);
assert.match(db, /rpc\('change_task_status'/);
assert.match(db, /rpc\('finalize_crm_deal_approval'/);
assert.match(db, /rpc\('assign_task'/);
assert.match(db, /rpc\('change_project_status'/);
assert.match(db, /rpc\('assign_project_team'/);
assert.match(app, /hrDomainServices\?\.deals\?\.changeStage/);
assert.match(app, /hrDomainServices\?\.deals\?\.markLost/);
assert.match(app, /hrDomainServices\?\.deals\?\.finalizeApproval/);
assert.match(app, /hrDomainServices\?\.deals\?\.startApproval/);
assert.match(app, /hrDomainServices\?\.tasks\?\.assign/);
assert.match(app, /hrDomainServices\?\.projects/);
assert.match(index, /js\/shared-services\.js/);
assert.match(sharedTypes, /export type DealStage/);
assert.match(sharedTypes, /export interface Task/);
assert.match(sharedServices, /createHrDomainServices/);
assert.match(browserBridge, /window\.hrDomainServices/);
assert.match(browserBridge, /assignTeam/);
assert.match(fileContracts, /ALLOWED_UPLOAD_MIME_TYPES/);
assert.match(authContract, /AuthSessionDto/);
assert.match(notificationContract, /DeviceRegistration/);

console.log('Backend/shared business logic readiness checks passed.');
