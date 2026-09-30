const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260928120000_notification_backend_services.sql'), 'utf8');
const applyScript = fs.readFileSync(path.join(root, 'supabase', 'staging', 'apply-notification-backend-services.ps1'), 'utf8');
const db = fs.readFileSync(path.join(root, 'js', 'db.js'), 'utf8');
const shared = fs.readFileSync(path.join(root, 'src', 'shared', 'notification-contract.ts'), 'utf8');
const services = fs.readFileSync(path.join(root, 'src', 'shared', 'domain-services.ts'), 'utf8');
const realtime = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20260905140000_notifications_realtime.sql'), 'utf8');
const pushFunction = fs.readFileSync(path.join(root, 'supabase', 'functions', 'push-notification-dispatcher', 'index.ts'), 'utf8');
const emailFunction = fs.readFileSync(path.join(root, 'supabase', 'functions', 'task-notification-email', 'index.js'), 'utf8');
const expiryFunction = fs.readFileSync(path.join(root, 'supabase', 'functions', 'document-expiry-notifier', 'index.js'), 'utf8');
const signedUrlFunction = fs.readFileSync(path.join(root, 'supabase', 'functions', 'file-signed-url', 'index.ts'), 'utf8');

const must = (condition, message) => {
  if (!condition) throw new Error(message);
};

must(migration.includes("ALTER TABLE public.push_subscriptions"), 'device schema extension missing');
for (const fn of [
  'list_my_notifications', 'get_my_notification', 'get_my_unread_notification_count',
  'mark_notification_read', 'mark_all_notifications_read', 'delete_my_notification',
  'create_notification_secure', 'register_notification_device',
  'update_notification_device_token', 'unregister_notification_device',
  'list_my_notification_devices'
]) must(migration.includes(`FUNCTION public.${fn}`), `${fn} missing`);
must(migration.includes('auth.uid()'), 'notification services do not derive caller identity');
must(migration.includes('REVOKE INSERT, UPDATE, DELETE ON public.notifications FROM authenticated'), 'notification table writes are not revoked');
must(migration.includes('REVOKE INSERT, UPDATE, DELETE, SELECT ON public.push_subscriptions FROM authenticated'), 'push table access is not revoked');
must(migration.includes("target_type', 'TASK"), 'task target metadata missing');
must(migration.includes("normalized_platform NOT IN ('web', 'ios', 'android')"), 'device platform allow-list missing');
must(applyScript.includes("$TargetRef = 'jcfyyxsuspukcmybyhjj'"), 'staging target guard missing');
must(applyScript.includes("$ProductionRef = 'bbbetcdioiaozdjkvwxu'"), 'production guard missing');
must(db.includes("rpc('list_my_notifications'"), 'web notification list does not use the authoritative RPC');
must(db.includes("rpc('get_my_notification'"), 'web notification detail does not use the authoritative RPC');
must(db.includes("rpc('mark_notification_read'"), 'web mark-read does not use the authoritative RPC');
must(db.includes("rpc('register_notification_device'"), 'web device registration does not use the authoritative RPC');
must(!db.includes("from('push_subscriptions').upsert"), 'web still performs direct push-subscription upsert');
must(shared.includes('NotificationListQuery'), 'shared notification pagination contract missing');
must(shared.includes('unreadCount'), 'shared unread-count contract missing');
must(services.includes('markAllRead'), 'shared mark-all-read service missing');
must(realtime.includes("ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications"), 'notifications are not in realtime publication');
must(pushFunction.includes('auth.getUser'), 'push dispatcher does not authenticate bearer tokens');
must(emailFunction.includes('auth.getUser'), 'task email dispatcher does not authenticate bearer tokens');
must(expiryFunction.includes('auth.getUser'), 'document expiry notifier does not authenticate bearer tokens');
must(signedUrlFunction.includes('auth.getUser'), 'signed-url function does not authenticate bearer tokens');
console.log('Notification backend static checks passed.');
