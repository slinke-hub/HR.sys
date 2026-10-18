const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const app = read('js/app.js');
const html = read('index.html');
const worker = read('sw.js');
const db = read('js/db.js');

const stageControlStart = app.indexOf('task-stage-select status-${taskStatusClass(task.status)}');
const stageControlEnd = app.indexOf('</select></label>', stageControlStart);
assert.ok(stageControlStart >= 0 && stageControlEnd > stageControlStart, 'Task card status editor exists');
const stageControl = app.slice(stageControlStart, stageControlEnd);
assert.match(stageControl, /Canceled — temporarily unavailable/,
  'Task card status editor explains cancellation is temporarily unavailable');
assert.match(stageControl, /\['late', 'canceled'\]\.includes\(String\(value\)\.toLowerCase\(\)\) \? 'disabled'/,
  'Late and canceled display options cannot be selected for submission');
assert.doesNotMatch(stageControl, /\.\.\.\(isCrmProposalDesignTask \? \[\['late'/,
  'Late is not offered as a new editable status');

const inlineStart = app.indexOf('const inlineStatusOptions = [');
const inlineEnd = app.indexOf('const inlineStatusSelect =', inlineStart);
assert.ok(inlineStart >= 0 && inlineEnd > inlineStart, 'Inline task status editor exists');
const inlineStatus = app.slice(inlineStart, inlineEnd + 700);
assert.match(inlineStatus, /Canceled — temporarily unavailable/,
  'Inline editor explains cancellation is temporarily unavailable');
assert.match(inlineStatus, /\['late', 'canceled'\]\.includes\(String\(value\)\.toLowerCase\(\)\) \? 'disabled'/,
  'Late and canceled values are disabled in the inline editor, including preserved current values');

const changeStageStart = app.indexOf('window.taskV2ChangeStage = async function');
const changeStageEnd = app.indexOf('\n};', changeStageStart);
assert.ok(changeStageStart >= 0 && changeStageEnd > changeStageStart, 'Shared task status handler exists');
const changeStage = app.slice(changeStageStart, changeStageEnd);
assert.match(changeStage, /requestedStatus[\s\S]*?canceled[\s\S]*?temporarily unavailable[\s\S]*?return \{ error:/,
  'Programmatic attempts to cancel are rejected with a bilingual warning');
assert.ok(changeStage.indexOf('temporarily unavailable') < changeStage.indexOf('window.handleUpdateTaskStatus'),
  'Canceled status is rejected before the RPC-backed update call');

assert.match(app, /if \(status === 'canceled'\) return 'canceled';|status: 'canceled'|\['canceled', 'cancelled'\]/,
  'Canceled status remains available for display and history');
assert.match(app, /<option value="canceled">\$\{taskDetailText\('Canceled', 'ملغاة'\)\}<\/option>/,
  'Canceled remains available as a task-list filter');
assert.match(app, /if \(normalized === 'late'\) return taskDetailText\('Late', 'متأخرة'\)/,
  'Late remains available as a display label');

assert.equal((html.match(/2026101802-production-task-manager-hotfix/g) || []).length, 2,
  'Both application script URLs use the hotfix cache version');
assert.match(app, /sw\.js\?v=2026101802-production-task-manager-hotfix/,
  'Service-worker registration uses the hotfix cache version');
assert.match(worker, /CACHE_NAME = 'muqam-hr-mobile-v256-production-task-manager-hotfix'/,
  'Service worker uses the hotfix-specific cache name');
assert.match(db, /SIGNED_STORAGE_NEGATIVE_TTL_MS = 30000/,
  'Signed-URL failures are cached only for the reviewed 30-second interval');
assert.match(db, /failedSignedStorageUrlCache = new Map\(\)/,
  'Failed signed-URL results use an in-memory negative cache');
assert.match(db, /signedStorageUrlRequests = new Map\(\)/,
  'Concurrent private URL resolutions share an in-flight request');
assert.match(db, /const cacheKey = `\$\{userId\}:\$\{reference\.bucket\}\/\$\{reference\.path\}`/,
  'Signed-URL cache entries are separated by authenticated user');
assert.match(db, /auth\.onAuthStateChange\(\(_event, session\) => \{[\s\S]*?clearSignedStorageUrlCaches\(session\?\.user\?\.id \|\| null\)/,
  'Authentication identity/session events invalidate signed-URL caches');
assert.match(db, /signedStorageCacheGeneration === requestGeneration[\s\S]*?signedStorageCacheUserId === userId/,
  'Late signed-URL responses are rejected after user or session changes');
assert.match(db, /body: \{ bucket: reference\.bucket, path: reference\.path, expiresIn: safeExpiresIn \}/,
  'The existing file-signed-url request contract is unchanged');
assert.match(db, /Math\.max\(60, Math\.min\(Number\(data\.expiresIn\) \|\| safeExpiresIn, 300\) - 60\) \* 1000/,
  'Positive signed-URL expiration remains unchanged');

console.log('Production Task Manager hotfix checks passed.');
