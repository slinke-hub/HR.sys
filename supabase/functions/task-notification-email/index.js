import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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

const attachmentName = (url, index) => {
  try {
    return decodeURIComponent(new URL(url).pathname.split("/").pop() || `Attachment ${index + 1}`).replace(/^\d+-/, "");
  } catch (_) {
    return `Attachment ${index + 1}`;
  }
};

const humanizeKey = (key) => String(key || "")
  .replaceAll("_", " ")
  .replace(/\b\w/g, (letter) => letter.toUpperCase());

const readableValue = (value) => {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "Yes" : "No";
  if (Array.isArray(value)) return value.length ? value.map(readableValue).join(", ") : "—";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
};

const detailEntries = (details) => Object.entries(details && typeof details === "object" ? details : {})
  .flatMap(([key, value]) => {
    if (value && typeof value === "object" && !Array.isArray(value)) {
      return Object.entries(value).map(([nestedKey, nestedValue]) => [`${humanizeKey(key)} · ${humanizeKey(nestedKey)}`, nestedValue]);
    }
    return [[humanizeKey(key), value]];
  })
  .filter(([, value]) => value !== null && value !== undefined && value !== "");

const textDetails = (details) => {
  const entries = detailEntries(details);
  return entries.length ? `\n\nDetails:\n${entries.map(([label, value]) => `- ${label}: ${readableValue(value)}`).join("\n")}` : "";
};

const htmlDetails = (details) => {
  const entries = detailEntries(details);
  if (!entries.length) return "";
  return `<div style="margin:18px 0;border:1px solid #dbe4f0;border-radius:10px;overflow:hidden"><div style="padding:10px 14px;background:#f4f7ff;font-weight:700">Details</div><table role="presentation" style="width:100%;border-collapse:collapse">${entries.map(([label, value]) => `<tr><td style="width:38%;padding:9px 14px;border-top:1px solid #e8edf5;color:#52627d;font-weight:600;vertical-align:top">${escapeHtml(label)}</td><td style="padding:9px 14px;border-top:1px solid #e8edf5;white-space:pre-wrap">${escapeHtml(readableValue(value))}</td></tr>`).join("")}</table></div>`;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
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
    .select("id,notification_id,task_id,recipient_email,subject,message,action_url,attempts,comment_text,attachment_links,always_send,context_type,details")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .limit(25);

  if (queueError) return json({ error: "Unable to read email queue" }, 500);
  if (!queued?.length) return json({ processed: 0, sent: 0, failed: 0 });

  const taskIds = [...new Set(queued.map((item) => item.task_id).filter(Boolean))];
  const { data: queuedTasks, error: taskDetailsError } = taskIds.length
    ? await admin.from("tasks").select("*").in("id", taskIds)
    : { data: [], error: null };
  if (taskDetailsError) return json({ error: "Unable to load task email details" }, 500);

  const { data: optedInTasks, error: optInError } = taskIds.length
    ? await admin.from("tasks").select("id").in("id", taskIds).eq("notify_via_email", true)
    : { data: [], error: null };
  if (optInError) return json({ error: "Unable to verify task email consent" }, 500);

  const optedInTaskIds = new Set((optedInTasks || []).map((task) => task.id));
  const eligible = queued.filter((item) => item.always_send === true || (item.task_id && optedInTaskIds.has(item.task_id)));
  const suppressedIds = queued
    .filter((item) => item.always_send !== true && (!item.task_id || !optedInTaskIds.has(item.task_id)))
    .map((item) => item.id);
  if (suppressedIds.length) {
    await admin.from("task_email_outbox").update({
      status: "cancelled",
      last_error: "Email was not requested by the task creator.",
    }).in("id", suppressedIds);
  }
  if (!eligible.length) return json({ processed: queued.length, sent: 0, failed: 0, suppressed: suppressedIds.length });

  const notificationIds = [...new Set(eligible.map((item) => item.notification_id).filter(Boolean))];
  const { data: queuedNotifications } = notificationIds.length
    ? await admin.from("notifications").select("id,actor_id,event_type").in("id", notificationIds)
    : { data: [] };
  const taskMap = new Map((queuedTasks || []).map((task) => [task.id, task]));
  const notificationMap = new Map((queuedNotifications || []).map((notification) => [notification.id, notification]));
  const profileIds = [...new Set([
    ...(queuedTasks || []).flatMap((task) => [task.created_by, task.assignee_id, task.supervisor_id]),
    ...(queuedNotifications || []).map((notification) => notification.actor_id),
  ].filter(Boolean))];
  const { data: relatedProfiles } = profileIds.length
    ? await admin.from("profiles").select("id,full_name,display_name,display_name_ar").in("id", profileIds)
    : { data: [] };
  const profileNameMap = new Map((relatedProfiles || []).map((profile) => [
    profile.id,
    profile.full_name || profile.display_name || profile.display_name_ar || "Unknown employee",
  ]));

  const ids = eligible.map((item) => item.id);
  await admin.from("task_email_outbox").update({ status: "processing" }).in("id", ids);

  let sent = 0;
  let failed = 0;
  for (const item of eligible) {
    try {
      const actionUrl = item.action_url && appUrl ? `${appUrl}${item.action_url}` : appUrl;
      const attachments = Array.isArray(item.attachment_links) ? item.attachment_links.filter(Boolean) : [];
      const commentText = String(item.comment_text || "").trim();
      const task = taskMap.get(item.task_id);
      const notification = notificationMap.get(item.notification_id);
      const taskFallbackDetails = task ? {
        "Task title": task.title,
        "Description": task.description,
        "Task creator": profileNameMap.get(task.created_by),
        "Updated by": profileNameMap.get(notification?.actor_id),
        "Assigned to": profileNameMap.get(task.assignee_id),
        "Supervisor": profileNameMap.get(task.supervisor_id),
        "Status": task.status,
        "Priority": task.priority,
        "Department": task.department,
        "Category": task.category,
        "Start date": task.start_date,
        "Due date": task.due_date || task.end_date,
        "Estimated time": task.estimated_time,
        "Event": notification?.event_type,
      } : {};
      const mergedDetails = { ...taskFallbackDetails, ...(item.details || {}) };
      const detailsText = textDetails(mergedDetails);
      const detailsHtml = htmlDetails(mergedDetails);
      const actionLabel = item.context_type === "EMPLOYEE_REQUEST" ? "Open employee request" : "Open task";
      const textAttachments = attachments.length ? `\n\nFiles:\n${attachments.map((url, index) => `- ${attachmentName(url, index)}: ${url}`).join("\n")}` : "";
      const htmlComment = commentText ? `<div style="margin:18px 0;padding:14px;border-left:4px solid #2563eb;background:#f4f7ff"><strong>Comment</strong><p style="white-space:pre-wrap;margin:7px 0 0">${escapeHtml(commentText)}</p></div>` : "";
      const htmlAttachments = attachments.length ? `<div style="margin:18px 0"><strong>Files</strong><ul style="padding-left:20px">${attachments.map((url, index) => `<li style="margin:8px 0"><a href="${escapeHtml(url)}" target="_blank" style="color:#2563eb;text-decoration:underline">Download ${escapeHtml(attachmentName(url, index))}</a></li>`).join("")}</ul></div>` : "";
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: fromAddress,
          to: [item.recipient_email],
          subject: item.subject,
          text: `${item.message}${detailsText}${commentText ? `\n\nComment:\n${commentText}` : ""}${textAttachments}${actionUrl ? `\n\n${actionLabel}: ${actionUrl}` : ""}`,
          html: `<div style="font-family:Arial,sans-serif;line-height:1.55;color:#172033"><h2 style="font-size:18px">${escapeHtml(item.subject)}</h2><p style="white-space:pre-wrap">${escapeHtml(item.message)}</p>${detailsHtml}${htmlComment}${htmlAttachments}${actionUrl ? `<p><a href="${escapeHtml(actionUrl)}" style="display:inline-block;padding:10px 16px;border-radius:7px;background:#2563eb;color:#fff;text-decoration:none">${escapeHtml(actionLabel)}</a></p>` : ""}</div>`,
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

  return json({ processed: queued.length, sent, failed, suppressed: suppressedIds.length });
});
