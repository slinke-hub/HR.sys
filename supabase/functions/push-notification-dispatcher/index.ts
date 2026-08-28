import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sys.muqam.net",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Credentials": "true",
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function nextOccurrence(dateValue: string, type: string, interval: number) {
  const date = new Date(dateValue);
  if (type === "MONTHLY") date.setUTCMonth(date.getUTCMonth() + 1);
  else date.setUTCDate(date.getUTCDate() + (type === "WEEKLY" ? 7 : type === "CUSTOM" ? Math.max(1, interval || 1) : 1));
  return date.toISOString();
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY") || "";
    const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY") || "";
    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY") || "";
    const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:info@muqam.net";
    if (!supabaseUrl || !serviceRoleKey) return response({ error: "Supabase service configuration is missing." }, 500);

    const authorization = request.headers.get("Authorization") || "";
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
    const token = authorization.replace(/^Bearer\s+/i, "");
    const { data: authData } = await admin.auth.getUser(token);
    if (!authData.user) return response({ error: "Unauthorized" }, 401);

    const input = await request.json().catch(() => ({}));
    if (input.action === "config") return response({ publicKey: vapidPublicKey });
    if (!vapidPublicKey || !vapidPrivateKey) return response({ error: "VAPID keys are not configured." }, 503);
    webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);

    let sent = 0;
    const sendToUser = async (userId: string, payload: Record<string, unknown>) => {
      const { data: subscriptions } = await admin.from("push_subscriptions").select("id,endpoint,p256dh,auth_key").eq("user_id", userId);
      let delivered = false;
      for (const item of subscriptions || []) {
        try {
          await webpush.sendNotification({ endpoint: item.endpoint, keys: { p256dh: item.p256dh, auth: item.auth_key } }, JSON.stringify(payload));
          delivered = true;
          sent += 1;
        } catch (error) {
          const statusCode = Number((error as { statusCode?: number })?.statusCode || 0);
          if (statusCode === 404 || statusCode === 410) await admin.from("push_subscriptions").delete().eq("id", item.id);
          else console.error("Push delivery failed", statusCode, error);
        }
      }
      return delivered;
    };

    const { data: notifications } = await admin.from("notifications")
      .select("id,user_id,message,created_at").is("push_sent_at", null).order("created_at").limit(100);
    for (const notification of notifications || []) {
      if (await sendToUser(notification.user_id, { title: "MUQAM HR", body: notification.message, url: "/?view=notifications", tag: `notification-${notification.id}` })) {
        await admin.from("notifications").update({ push_sent_at: new Date().toISOString() }).eq("id", notification.id);
      }
    }

    const now = new Date().toISOString();
    const { data: reminders } = await admin.from("reminders").select("*")
      .eq("status", "pending").lte("due_date", now).is("last_notified_at", null).limit(100);
    for (const reminder of reminders || []) {
      const delivered = await sendToUser(reminder.user_id, { title: reminder.title, body: reminder.description || "Reminder due now", url: "/?view=schedule", tag: `reminder-${reminder.id}` });
      if (!delivered) continue;
      if (reminder.recurrence_type && reminder.recurrence_type !== "NONE") {
        await admin.from("reminders").update({ due_date: nextOccurrence(reminder.due_date, reminder.recurrence_type, reminder.recurrence_interval), last_notified_at: null }).eq("id", reminder.id);
      } else {
        await admin.from("reminders").update({ last_notified_at: new Date().toISOString() }).eq("id", reminder.id);
      }
    }
    return response({ success: true, sent });
  } catch (error) {
    console.error(error);
    return response({ error: error instanceof Error ? error.message : "Push dispatch failed" }, 500);
  }
});
