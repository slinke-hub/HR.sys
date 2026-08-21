import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

const escapeHtml = (value) => String(value || "")
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#039;");

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const fromAddress = Deno.env.get("TASK_EMAIL_FROM") || "MUQAM Tasks <no-reply@muqam.net>";
  const appUrl = (Deno.env.get("APP_URL") || "").replace(/\/$/, "");
  const authorization = request.headers.get("Authorization") || "";

  if (!supabaseUrl || !serviceRoleKey || !resendApiKey) {
    return json({ error: "Task email service is not configured" }, 503);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authorization.replace(/^Bearer\s+/i, "");
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData?.user) return json({ error: "Unauthorized" }, 401);

  const { data: queued, error: queueError } = await admin
    .from("task_email_outbox")
    .select("id,recipient_email,subject,message,action_url,attempts")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .limit(25);

  if (queueError) return json({ error: "Unable to read email queue" }, 500);
  if (!queued?.length) return json({ processed: 0, sent: 0, failed: 0 });

  const ids = queued.map((item) => item.id);
  await admin.from("task_email_outbox").update({ status: "processing" }).in("id", ids);

  let sent = 0;
  let failed = 0;
  for (const item of queued) {
    try {
      const actionUrl = item.action_url && appUrl ? `${appUrl}${item.action_url}` : appUrl;
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: fromAddress,
          to: [item.recipient_email],
          subject: item.subject,
          text: `${item.message}${actionUrl ? `\n\nOpen task: ${actionUrl}` : ""}`,
          html: `<div style="font-family:Arial,sans-serif;line-height:1.55;color:#172033"><h2 style="font-size:18px">${escapeHtml(item.subject)}</h2><p>${escapeHtml(item.message)}</p>${actionUrl ? `<p><a href="${escapeHtml(actionUrl)}" style="display:inline-block;padding:10px 16px;border-radius:7px;background:#2563eb;color:#fff;text-decoration:none">Open task</a></p>` : ""}</div>`,
        }),
      });
      if (!response.ok) throw new Error(`Resend returned ${response.status}: ${await response.text()}`);
      await admin.from("task_email_outbox").update({ status: "sent", sent_at: new Date().toISOString(), last_error: null, attempts: (item.attempts || 0) + 1 }).eq("id", item.id);
      sent += 1;
    } catch (error) {
      await admin.from("task_email_outbox").update({ status: "failed", last_error: String(error?.message || error).slice(0, 1000), attempts: (item.attempts || 0) + 1 }).eq("id", item.id);
      failed += 1;
    }
  }

  return json({ processed: queued.length, sent, failed });
});
