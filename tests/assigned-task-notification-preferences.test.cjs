const assert = require('node:assert/strict');
const fs = require('node:fs');

const app = fs.readFileSync('js/app.js', 'utf8');
const db = fs.readFileSync('js/db.js', 'utf8');
const migration = fs.readFileSync(
  'supabase/migrations/20261107100000_assignee_task_notifications_and_sound_preferences.sql',
  'utf8'
);

assert.match(app, /id="profileNotificationSoundEnabled"[^>]*onchange="window\.saveNotificationSoundPreference\(this\)"/);
assert.match(app, /if\s*\(!notificationSoundEnabled\s*\|\|\s*!notificationSoundUnlocked/);
assert.match(app, /notificationSoundEnabled\s*=\s*soundPreference\.enabled/);
assert.match(db, /async getMyNotificationSoundPreference\(\)[\s\S]*?from\('user_notification_preferences'\)[\s\S]*?select\('sound_enabled'\)/);
assert.match(db, /async setMyNotificationSoundPreference\(enabled\)[\s\S]*?supabaseClient\.auth\.getUser\(\)[\s\S]*?upsert\(\{ user_id: userId, sound_enabled: enabled === true \}/);

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.user_notification_preferences[\s\S]*?sound_enabled boolean NOT NULL DEFAULT true/);
assert.match(migration, /CREATE POLICY user_notification_preferences_select_self[\s\S]*?USING \(user_id = auth\.uid\(\)\)/);
assert.match(migration, /CREATE POLICY user_notification_preferences_insert_self[\s\S]*?WITH CHECK \(user_id = auth\.uid\(\)\)/);
assert.match(migration, /CREATE POLICY user_notification_preferences_update_self[\s\S]*?USING \(user_id = auth\.uid\(\)\)[\s\S]*?WITH CHECK \(user_id = auth\.uid\(\)\)/);
assert.match(migration, /REVOKE ALL ON TABLE public\.user_notification_preferences FROM PUBLIC, anon, authenticated/);
assert.match(migration, /GRANT SELECT, INSERT, UPDATE ON TABLE public\.user_notification_preferences TO authenticated/);
assert.doesNotMatch(migration, /GRANT\s+[^;]*\bDELETE\b[^;]*ON TABLE public\.user_notification_preferences/i);

assert.match(migration, /CREATE TRIGGER employee_task_notification_assignment_guard\s+BEFORE INSERT ON public\.notifications/);
assert.match(migration, /CREATE TRIGGER employee_task_email_assignment_guard\s+BEFORE INSERT ON public\.task_email_outbox/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.enforce_employee_task_notification_assignment\(\) FROM PUBLIC, anon, authenticated, service_role/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.enforce_employee_task_email_assignment\(\) FROM PUBLIC, anon, authenticated, service_role/);
assert.match(migration, /IF recipient_role IS NULL THEN\s+RETURN NULL;/);
assert.match(migration, /recipient_role := NULLIF\(recipient_role, ''\);\s+IF recipient_role IS NULL THEN\s+RETURN NULL;/);
assert.match(migration, /IF recipient_role <> 'EMPLOYEE' THEN\s+RETURN NEW;/);
assert.match(migration, /task_row\.assignee_id = NEW\.user_id[\s\S]*?NEW\.user_id = ANY\(COALESCE\(task_row\.assignee_ids/);
assert.match(migration, /IF COALESCE\(recipient_is_assigned, false\) IS NOT TRUE THEN\s+-- Suppress the row[\s\S]*?RETURN NULL;/);
assert.match(migration, /CREATE POLICY employee_task_notification_assignment_read_guard\s+ON public\.notifications\s+AS RESTRICTIVE\s+FOR SELECT TO authenticated/);
assert.match(migration, /task_row\.assignee_id = auth\.uid\(\)[\s\S]*?auth\.uid\(\) = ANY\(COALESCE\(task_row\.assignee_ids/);
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.enforce_employee_task_email_assignment\(\)[\s\S]*?NEW\.recipient_id = ANY\(COALESCE\(task_row\.assignee_ids/);
assert.equal((migration.match(/OR EXISTS \([\s\S]*?task_row\.assignee_id = auth\.uid\(\)/g) || []).length, 4);

console.log('Employee task notifications are assignment-scoped and ringtone preferences are owner-only.');
