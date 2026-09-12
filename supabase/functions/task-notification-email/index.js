import { createClient } from "npm:@supabase/supabase-js@2";

const isAllowedOrigin = (origin) => {
  if (origin === "https://sys.muqam.net") return true;
  try {
    const parsed = new URL(origin);
    return ["localhost", "127.0.0.1"].includes(parsed.hostname) && ["http:", "https:", "capacitor:"].includes(parsed.protocol);
  } catch (_) {
    return false;
  }
};

const corsHeadersFor = (request) => {
  const origin = request.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": isAllowedOrigin(origin) ? origin : "https://sys.muqam.net",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-dispatch-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
};

const secureEqual = (left, right) => {
  if (!left || !right || left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
};

const escapeHtml = (value) => String(value || "")
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#039;");

const attachmentName = (url, index = 0) => {
  if (!url || typeof url !== "string") return `Attachment ${index + 1}`;
  if (url.startsWith("data:")) {
    const isImg = url.startsWith("data:image/");
    return isImg ? `Photo_${index + 1}` : `Document_${index + 1}`;
  }
  try {
    const parsed = new URL(url);
    const lastPart = parsed.pathname.split("/").pop() || "";
    const clean = decodeURIComponent(lastPart).replace(/^\d+-/, "");
    return clean || `Attachment ${index + 1}`;
  } catch (_) {
    const lastPart = url.split("/").pop() || "";
    return decodeURIComponent(lastPart).replace(/^\d+-/, "") || `Attachment ${index + 1}`;
  }
};

const isImageFile = (url, name) => {
  if (typeof url === "string" && url.startsWith("data:image/")) return true;
  const clean = String(name || url || "").split("?")[0].toLowerCase();
  return /\.(jpg|jpeg|png|gif|webp|svg|bmp|ico|heic|heif)$/i.test(clean);
};

const fileIcon = (fileName) => {
  const ext = String(fileName || "").split(".").pop()?.toLowerCase();
  if (["pdf"].includes(ext)) return "📄";
  if (["xls", "xlsx", "csv"].includes(ext)) return "📊";
  if (["doc", "docx", "txt", "rtf"].includes(ext)) return "📝";
  if (["zip", "rar", "7z", "tar", "gz"].includes(ext)) return "📦";
  if (["mp4", "mov", "avi", "webm"].includes(ext)) return "🎬";
  if (["mp3", "wav", "m4a"].includes(ext)) return "🎵";
  return "📎";
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

// Helper: resolve storage references (storage://bucket/path), base64 data URIs, and sign private URLs
async function resolveAttachment(admin, rawItem, index = 0) {
  let rawUrl = typeof rawItem === "string" ? rawItem : rawItem?.url || rawItem?.file_url;
  let rawName = typeof rawItem === "object" ? rawItem?.name || rawItem?.file_name : null;
  if (!rawUrl || typeof rawUrl !== "string") return null;

  rawUrl = rawUrl.trim();
  if (!rawName) {
    rawName = attachmentName(rawUrl, index);
  }

  // Handle data URIs (e.g. expense receipts)
  if (rawUrl.startsWith("data:")) {
    try {
      const match = rawUrl.match(/^data:([^;]+);base64,(.+)$/);
      if (match) {
        const mimeType = match[1];
        const base64Content = match[2];
        const ext = mimeType.split("/")[1]?.replace("jpeg", "jpg") || "png";
        const cleanBaseName = rawName.replace(/[^a-zA-Z0-9._-]/g, "_").replace(/\.[^/.]+$/, "");
        const uploadPath = `email-assets/${Date.now()}-${cleanBaseName}.${ext}`;
        const binary = Uint8Array.from(atob(base64Content), (c) => c.charCodeAt(0));

        // Upload to task-attachments bucket so email clients can display the photo directly
        const { error: uploadError } = await admin.storage
          .from("task-attachments")
          .upload(uploadPath, binary, { contentType: mimeType, upsert: true });

        if (!uploadError) {
          const { data: signedData } = await admin.storage
            .from("task-attachments")
            .createSignedUrl(uploadPath, 60 * 60 * 24 * 7); // valid 7 days

          if (signedData?.signedUrl) {
            return {
              name: rawName,
              url: signedData.signedUrl,
              previewUrl: signedData.signedUrl,
              isImage: mimeType.startsWith("image/"),
              mimeType,
              base64Content,
            };
          }
        }
      }
    } catch (e) {
      console.warn("Could not process base64 data URI for email attachment:", e);
    }
    const isImg = rawUrl.startsWith("data:image/");
    return {
      name: rawName,
      url: rawUrl,
      previewUrl: rawUrl,
      isImage: isImg,
    };
  }

  // Handle storage://bucket/path
  let bucket = null;
  let path = null;
  const storageMatch = rawUrl.match(/^storage:\/\/([^/]+)\/(.+)$/);
  if (storageMatch) {
    bucket = storageMatch[1];
    path = storageMatch[2];
  } else if (rawUrl.includes("/storage/v1/object/")) {
    try {
      const parsed = new URL(rawUrl);
      const marker = "/storage/v1/object/";
      const idx = parsed.pathname.indexOf(marker);
      if (idx >= 0) {
        const after = parsed.pathname.slice(idx + marker.length);
        const parts = after.split("/").filter(Boolean);
        if (["public", "authenticated", "sign"].includes(parts[0])) {
          bucket = parts[1];
          path = parts.slice(2).join("/");
        } else {
          bucket = parts[0];
          path = parts.slice(1).join("/");
        }
      }
    } catch (_) {}
  }

  if (bucket && path) {
    try {
      const { data: signedData, error: signError } = await admin.storage
        .from(bucket)
        .createSignedUrl(decodeURIComponent(path), 60 * 60 * 24 * 7);

      if (!signError && signedData?.signedUrl) {
        const resolvedUrl = signedData.signedUrl;
        const isImg = isImageFile(resolvedUrl, rawName);
        return {
          name: rawName,
          url: resolvedUrl,
          previewUrl: resolvedUrl,
          isImage: isImg,
        };
      }
    } catch (e) {
      console.warn("Could not sign storage URL:", e);
    }
  }

  const isImg = isImageFile(rawUrl, rawName);
  return {
    name: rawName,
    url: rawUrl,
    previewUrl: rawUrl,
    isImage: isImg,
  };
}

Deno.serve(async (request) => {
  const corsHeaders = corsHeadersFor(request);
  const json = (body, status = 200) => new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
  if (request.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const fromAddress = Deno.env.get("TASK_EMAIL_FROM") || "MUQAM Tasks <no-reply@muqam.net>";
  const appUrl = (Deno.env.get("APP_URL") || "https://sys.muqam.net").replace(/\/$/, "");
  const authorization = request.headers.get("Authorization") || "";
  const configuredDispatchSecret = Deno.env.get("TASK_EMAIL_DISPATCH_SECRET") || "";
  const suppliedDispatchSecret = request.headers.get("X-Dispatch-Secret") || "";

  if (!supabaseUrl || !serviceRoleKey || !resendApiKey) {
    return json({ error: "Task email service is not configured" }, 503);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authorization.replace(/^Bearer\s+/i, "");
  const isServiceRole = Boolean(serviceRoleKey && token && secureEqual(serviceRoleKey, token));
  const { data: authData, error: authError } = token && !isServiceRole
    ? await admin.auth.getUser(token)
    : { data: { user: null }, error: null };
  const isTrustedDispatcher = secureEqual(configuredDispatchSecret, suppliedDispatchSecret) || isServiceRole;
  if ((authError || !authData?.user) && !isTrustedDispatcher) return json({ error: "Unauthorized" }, 401);

  let canProcessAll = isTrustedDispatcher;
  if (authData?.user && !canProcessAll) {
    const { data: callerProfile } = await admin.from("profiles").select("role,job_title").eq("id", authData.user.id).maybeSingle();
    const accessValues = [callerProfile?.role, callerProfile?.job_title]
      .map((value) => String(value || "").trim().toUpperCase().replaceAll("_", " ").replaceAll("-", " "));
    canProcessAll = accessValues.some((value) =>
      ["ADMIN", "OWNER", "ROLE SYSTEM ADMIN", "SYSTEM ADMIN", "CEO", "GM", "GENERAL MANAGER"].includes(value)
    );
  }

  const { data: queuedRows, error: queueError } = await admin
    .from("task_email_outbox")
    .select("id,notification_id,task_id,recipient_email,subject,message,action_url,attempts,comment_text,attachment_links,always_send,context_type,details")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .limit(100);

  if (queueError) return json({ error: "Unable to read email queue" }, 500);
  let queued = queuedRows || [];
  if (!queued.length) return json({ processed: 0, sent: 0, failed: 0 });

  const notificationIds = [...new Set(queued.map((item) => item.notification_id).filter(Boolean))];
  const { data: queuedNotifications } = notificationIds.length
    ? await admin.from("notifications").select("id,actor_id,event_type,metadata").in("id", notificationIds)
    : { data: [] };
  const notificationMap = new Map((queuedNotifications || []).map((notification) => [notification.id, notification]));
  if (!canProcessAll) {
    queued = queued.filter((item) => notificationMap.get(item.notification_id)?.actor_id === authData.user.id);
    if (!queued.length) return json({ processed: 0, sent: 0, failed: 0 });
  }

  const taskIds = [...new Set(queued.map((item) => item.task_id).filter(Boolean))];
  const { data: queuedTasks, error: taskDetailsError } = taskIds.length
    ? await admin.from("tasks").select("*").in("id", taskIds)
    : { data: [], error: null };
  if (taskDetailsError) return json({ error: "Unable to load task email details" }, 500);

  // Fetch extra task attachments from public.task_attachments table if table exists
  const { data: dbTaskAttachments } = taskIds.length
    ? await admin.from("task_attachments").select("task_id, file_url, file_name").in("task_id", taskIds)
    : { data: [] };
  const taskAttachmentsMap = new Map();
  (dbTaskAttachments || []).forEach((row) => {
    const list = taskAttachmentsMap.get(row.task_id) || [];
    list.push({ url: row.file_url, name: row.file_name });
    taskAttachmentsMap.set(row.task_id, list);
  });

  // Fetch task comment attachments if any
  const { data: dbTaskComments } = taskIds.length
    ? await admin.from("task_comments").select("task_id, attachments").in("task_id", taskIds)
    : { data: [] };
  const commentAttachmentsMap = new Map();
  (dbTaskComments || []).forEach((row) => {
    if (Array.isArray(row.attachments) && row.attachments.length) {
      const list = commentAttachmentsMap.get(row.task_id) || [];
      row.attachments.forEach((att) => {
        if (att) list.push(att);
      });
      commentAttachmentsMap.set(row.task_id, list);
    }
  });

  // Fetch expense receipts for any expense employee requests
  const expenseIds = [...new Set(
    (queuedNotifications || [])
      .filter((n) => n?.metadata?.source_table === "expenses" && n?.metadata?.source_id)
      .map((n) => n.metadata.source_id)
  )];
  const { data: dbExpenses } = expenseIds.length
    ? await admin.from("expenses").select("id, receipt_base64, description, amount").in("id", expenseIds)
    : { data: [] };
  const expenseMap = new Map((dbExpenses || []).map((exp) => [exp.id, exp]));

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

  const taskMap = new Map((queuedTasks || []).map((task) => [task.id, task]));
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
      const commentText = String(item.comment_text || "").trim();
      const task = taskMap.get(item.task_id);
      const notification = notificationMap.get(item.notification_id);

      // Normalize action URL so it directs to the exact task or request page on the app
      let rawAction = item.action_url || "";
      if (rawAction.startsWith("/tasks-v2?task=")) {
        rawAction = `/?view=tasks&task=${rawAction.split("/tasks-v2?task=")[1]}`;
      } else if (item.task_id && !rawAction.includes("task=")) {
        rawAction = `/?view=tasks&task=${item.task_id}`;
      } else if (item.context_type === "EMPLOYEE_REQUEST") {
        const reqId = notification?.metadata?.source_id || item.metadata?.source_id;
        if (!rawAction) {
          rawAction = reqId ? `/?view=requests&request=${reqId}` : "/?view=requests";
        } else if (reqId && !rawAction.includes("request=")) {
          rawAction = `${rawAction}${rawAction.includes("?") ? "&" : "?"}request=${reqId}`;
        }
      }
      const actionUrl = rawAction && appUrl
        ? `${appUrl}${rawAction.startsWith("/") ? "" : "/"}${rawAction}`
        : (item.task_id ? `${appUrl}/?view=tasks&task=${item.task_id}` : appUrl);

      // Collect all candidate attachments for this outbox item
      const candidateAttachments = [];
      if (Array.isArray(item.attachment_links)) {
        for (const att of item.attachment_links) {
          if (att) candidateAttachments.push(att);
        }
      }

      if (item.task_id) {
        const fromDb = taskAttachmentsMap.get(item.task_id) || [];
        for (const a of fromDb) if (a) candidateAttachments.push(a);

        if (task) {
          if (Array.isArray(task.submission_links)) {
            for (const l of task.submission_links) if (l) candidateAttachments.push(l);
          }
          if (Array.isArray(task.content_links)) {
            for (const l of task.content_links) if (l) candidateAttachments.push(l);
          }
          if (task.upload_link) candidateAttachments.push(task.upload_link);
          if (task.source_link) candidateAttachments.push(task.source_link);
          if (Array.isArray(task.attachments)) {
            for (const a of task.attachments) if (a) candidateAttachments.push(a);
          }
        }

        const fromComments = commentAttachmentsMap.get(item.task_id) || [];
        for (const a of fromComments) if (a) candidateAttachments.push(a);
      }

      // Check for expense receipts or request attachments
      if (notification?.metadata?.source_table === "expenses" && notification?.metadata?.source_id) {
        const exp = expenseMap.get(notification.metadata.source_id);
        if (exp?.receipt_base64) {
          candidateAttachments.push({
            url: exp.receipt_base64,
            name: `Receipt - ${exp.description || "Expense"}`,
          });
        }
      }

      // Deduplicate and resolve attachments (generate signed URLs & upload base64 images if needed)
      const resolvedAttachments = [];
      const seenUrls = new Set();
      for (let i = 0; i < candidateAttachments.length; i += 1) {
        const raw = candidateAttachments[i];
        const rawUrl = typeof raw === "string" ? raw : raw?.url || raw?.file_url;
        if (!rawUrl || seenUrls.has(rawUrl)) continue;
        seenUrls.add(rawUrl);

        const resolved = await resolveAttachment(admin, raw, i);
        if (resolved && resolved.url) {
          resolvedAttachments.push(resolved);
        }
      }

      const photos = resolvedAttachments.filter((a) => a.isImage);
      const documents = resolvedAttachments.filter((a) => !a.isImage);

      // Determine Employee Name: creator, updater, or request sender
      const creatorName = profileNameMap.get(task?.created_by) || null;
      const actorName = profileNameMap.get(notification?.actor_id) || null;
      const requestEmployeeName = (item.details ? (item.details["Employee"] || item.details["Action by"]) : null) || (notification?.metadata?.employee_name || null);

      let primaryEmployeeName = "Employee";
      let employeeRoleLabel = "Initiated by";

      if (item.context_type === "EMPLOYEE_REQUEST") {
        primaryEmployeeName = requestEmployeeName || actorName || "Employee";
        employeeRoleLabel = "Request Sent by";
      } else if (notification?.event_type === "task_comment") {
        primaryEmployeeName = actorName || creatorName || "Team Member";
        employeeRoleLabel = "Comment Posted by";
      } else if (notification?.event_type === "task_created" || !actorName) {
        primaryEmployeeName = creatorName || actorName || "Task Creator";
        employeeRoleLabel = "Task Created by";
      } else {
        primaryEmployeeName = actorName || creatorName || "Team Member";
        employeeRoleLabel = "Task Updated by";
      }

      const taskFallbackDetails = task ? {
        "Task title": task.title,
        "Description": task.description,
        "Task creator": creatorName || "—",
        "Updated by": actorName || creatorName || "—",
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

      const htmlComment = commentText ? `<div style="margin:18px 0;padding:14px;border-left:4px solid #2563eb;background:#f4f7ff"><strong>Comment</strong><p style="white-space:pre-wrap;margin:7px 0 0">${escapeHtml(commentText)}</p></div>` : "";

      // Render Photo & Image Gallery
      let photosHtml = "";
      if (photos.length > 0) {
        photosHtml = `
          <div style="margin:24px 0 16px 0;">
            <div style="font-weight:700;font-size:15px;color:#111827;margin-bottom:12px;border-bottom:1px solid #e5e7eb;padding-bottom:6px;">
              📷 Photos &amp; Images (${photos.length})
            </div>
            ${photos.map((photo) => `
              <div style="margin-bottom:16px;background:#ffffff;border:1px solid #e5e7eb;border-radius:10px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.05);">
                <div style="text-align:center;background:#f9fafb;padding:14px;line-height:0;">
                  <a href="${escapeHtml(photo.url)}" target="_blank" style="display:inline-block;max-width:100%;text-decoration:none;">
                    <img src="${escapeHtml(photo.previewUrl || photo.url)}" alt="${escapeHtml(photo.name)}" style="max-width:100%;max-height:360px;height:auto;border-radius:6px;object-fit:contain;display:block;margin:0 auto;border:1px solid #e5e7eb;" />
                  </a>
                </div>
                <table role="presentation" style="width:100%;border-collapse:collapse;background:#ffffff;border-top:1px solid #e5e7eb;">
                  <tr>
                    <td style="padding:10px 14px;font-size:13px;font-weight:600;color:#374151;word-break:break-all;">
                      ${escapeHtml(photo.name)}
                    </td>
                    <td style="padding:10px 14px;text-align:right;white-space:nowrap;">
                      <a href="${escapeHtml(photo.url)}" target="_blank" style="display:inline-block;font-size:12px;font-weight:600;color:#2563eb;background:#eff6ff;padding:6px 14px;border-radius:6px;text-decoration:none;">View / Download</a>
                    </td>
                  </tr>
                </table>
              </div>
            `).join("")}
          </div>
        `;
      }

      // Render Attached Documents & Files
      let documentsHtml = "";
      if (documents.length > 0) {
        documentsHtml = `
          <div style="margin:24px 0 16px 0;">
            <div style="font-weight:700;font-size:15px;color:#111827;margin-bottom:12px;border-bottom:1px solid #e5e7eb;padding-bottom:6px;">
              📎 Attached Files &amp; Documents (${documents.length})
            </div>
            ${documents.map((doc) => `
              <table role="presentation" style="width:100%;border-collapse:collapse;background:#ffffff;border:1px solid #e5e7eb;border-radius:8px;margin-bottom:8px;">
                <tr>
                  <td style="padding:12px 14px;width:32px;font-size:20px;vertical-align:middle;">
                    ${fileIcon(doc.name)}
                  </td>
                  <td style="padding:12px 14px;font-size:13px;font-weight:600;color:#1f2937;word-break:break-all;vertical-align:middle;">
                    ${escapeHtml(doc.name)}
                  </td>
                  <td style="padding:12px 14px;text-align:right;white-space:nowrap;vertical-align:middle;">
                    <a href="${escapeHtml(doc.url)}" target="_blank" style="display:inline-block;font-size:12px;font-weight:600;color:#2563eb;background:#eff6ff;padding:6px 14px;border-radius:6px;text-decoration:none;">Download</a>
                  </td>
                </tr>
              </table>
            `).join("")}
          </div>
        `;
      }

      const htmlAttachments = `${photosHtml}${documentsHtml}`;
      const textAttachments = resolvedAttachments.length
        ? `\n\nAttachments & Files:\n${resolvedAttachments.map((att) => `- ${att.name}: ${att.url}`).join("\n")}`
        : "";

      const textMessage = `${primaryEmployeeName} (${employeeRoleLabel}): ${item.message}`;
      const htmlMessage = escapeHtml(item.message);

      let approvalButtonsHtml = "";
      if (item.context_type === "EMPLOYEE_REQUEST" && notification?.metadata?.workflow_id) {
        const approveUrl = `${actionUrl}&email_action=APPROVE&workflow_id=${notification.metadata.workflow_id}&source_table=${notification.metadata.source_table}&source_id=${notification.metadata.source_id}`;
        const rejectUrl = `${actionUrl}&email_action=REJECT&workflow_id=${notification.metadata.workflow_id}&source_table=${notification.metadata.source_table}&source_id=${notification.metadata.source_id}`;
        approvalButtonsHtml = `
          <div style="margin-top: 24px; padding-top: 24px; border-top: 1px solid #e5e7eb;">
            <p style="margin-bottom: 12px; font-weight: bold; color: #374151;">Quick Actions:</p>
            <a href="${escapeHtml(approveUrl)}" style="display:inline-block;padding:12px 24px;border-radius:7px;background:#10b981;color:#fff;text-decoration:none;font-weight:600;margin-right:12px;">Approve</a>
            <a href="${escapeHtml(rejectUrl)}" style="display:inline-block;padding:12px 24px;border-radius:7px;background:#ef4444;color:#fff;text-decoration:none;font-weight:600;">Reject</a>
          </div>
        `;
      }

      // Enhanced HTML Email Template with Prominent Employee Banner, Photo Gallery, and Hyperlink
      const emailLayoutHtml = `
      <div style="font-family:Arial,sans-serif;line-height:1.6;color:#374151;background-color:#f9fafb;padding:40px 20px;">
        <div style="max-width:600px;margin:0 auto;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);border:1px solid #e5e7eb;">
          <div style="padding:32px;">
            <h2 style="margin-top:0;font-size:22px;color:#111827;">${escapeHtml(item.subject)}</h2>

            <!-- Employee Info Banner -->
            <div style="margin: 0 0 24px 0; padding: 14px 18px; background: #f0f7ff; border: 1px solid #bfdbfe; border-radius: 10px;">
              <table role="presentation" style="width: 100%; border-collapse: collapse;">
                <tr>
                  <td style="width: 44px; vertical-align: middle;">
                    <div style="width: 40px; height: 40px; border-radius: 50%; background: #2563eb; color: #ffffff; text-align: center; line-height: 40px; font-size: 18px; font-weight: 700;">
                      ${escapeHtml((primaryEmployeeName || "E").charAt(0).toUpperCase())}
                    </div>
                  </td>
                  <td style="vertical-align: middle; padding-left: 12px;">
                    <div style="font-size: 12px; font-weight: 700; color: #1e40af; text-transform: uppercase; letter-spacing: 0.5px;">
                      ${escapeHtml(employeeRoleLabel)}
                    </div>
                    <div style="font-size: 16px; font-weight: 700; color: #0f172a; margin-top: 2px;">
                      ${escapeHtml(primaryEmployeeName)}
                    </div>
                  </td>
                </tr>
              </table>
            </div>

            <p style="font-size:16px;white-space:pre-wrap;margin-bottom:24px;">${htmlMessage}</p>

            ${detailsHtml ? `<div style="background:#f9fafb;border-radius:8px;padding:20px;margin-bottom:24px;border:1px solid #f3f4f6;">${detailsHtml}</div>` : ""}
            ${htmlComment}
            ${htmlAttachments}

            <!-- Direct Hyperlink to Task / Request on App -->
            ${actionUrl ? `
              <div style="margin-top:28px;padding-top:22px;border-top:1px solid #e5e7eb;text-align:center;">
                <a href="${escapeHtml(actionUrl)}" target="_blank" style="display:inline-block;padding:14px 32px;border-radius:8px;background:#2563eb;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;box-shadow:0 4px 6px -1px rgba(37, 99, 235, 0.25);">
                  ${escapeHtml(actionLabel)} →
                </a>
                <div style="margin-top:12px;font-size:13px;color:#6b7280;">
                  Direct link: <a href="${escapeHtml(actionUrl)}" target="_blank" style="color:#2563eb;text-decoration:underline;word-break:break-all;font-weight:500;">${escapeHtml(actionUrl)}</a>
                </div>
              </div>
            ` : ""}

            ${approvalButtonsHtml}
          </div>
        </div>
      </div>`;

      // Build Resend attachment payload if any
      const resendAttachments = [];
      for (const att of resolvedAttachments) {
        if (att.base64Content) {
          resendAttachments.push({
            filename: att.name,
            content: att.base64Content,
          });
        } else if (att.url && (att.url.startsWith("http://") || att.url.startsWith("https://"))) {
          resendAttachments.push({
            filename: att.name,
            path: att.url,
          });
        }
      }

      const emailPayload = {
        from: fromAddress,
        to: [item.recipient_email],
        subject: item.subject,
        text: `${textMessage}${detailsText}${commentText ? `\n\nComment:\n${commentText}` : ""}${textAttachments}${actionUrl ? `\n\n${actionLabel}: ${actionUrl}` : ""}`,
        html: emailLayoutHtml,
      };

      if (resendAttachments.length > 0) {
        emailPayload.attachments = resendAttachments.slice(0, 5);
      }

      let response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(emailPayload),
      });

      // Fallback: If Resend returns an error when attachments are included, retry without attachment array
      if (!response.ok && emailPayload.attachments) {
        console.warn("Resend attachments send failed, retrying without attachment array...");
        delete emailPayload.attachments;
        response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify(emailPayload),
        });
      }

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
