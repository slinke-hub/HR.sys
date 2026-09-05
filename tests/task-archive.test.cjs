/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'js', 'app.js'), 'utf8');
const dbSource = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260905230500_archive_completed_tasks.sql'), 'utf8');

assert.match(html, /data-view="archived_tasks"/);
assert.match(app, /case 'archived_tasks': content = await renderArchivedTasks\(\)/);
assert.match(app, /fetchedTasks\.filter\(t => !t\.archived_at\)/);
assert.match(dbSource, /async fetchArchivedTasks\(\)/);
assert.match(dbSource, /\.not\('archived_at', 'is', null\)/);
assert.match(migration, /ADD COLUMN IF NOT EXISTS archived_at timestamptz/i);
assert.match(migration, /lower\(btrim\(coalesce\(status, ''\)\)\) IN \('completed', 'approved'\)/i);
assert.match(migration, /archive-completed-tasks-after-11pm/);
assert.match(migration, /'5 20 \* \* \*'/);
assert.match(migration, /SELECT public\.archive_completed_tasks\(\);/);

console.log('Task archive checks passed.');
