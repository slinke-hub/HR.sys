import { createClient } from "npm:@supabase/supabase-js@2";

const DAY_IN_MS = 86_400_000;
const ACTIVE = "Active";
const EXPIRES_SOON = "Expires Soon";
const EXPIRED = "Expired";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function requiredEnv(name) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

function jsonResponse(body, status = 200) {
  return Response.json(body, {
    status,
    headers: { ...corsHeaders, "Cache-Control": "no-store" },
  });
}

function isUuid(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function getSupabaseAdminKey() {
  const directKey =
    Deno.env.get("SUPABASE_SECRET_KEY") ||
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (directKey) return directKey;

  const namedKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (namedKeys) {
    const parsedKeys = JSON.parse(namedKeys);
    const selectedKey = parsedKeys.default || Object.values(parsedKeys)[0];
    if (typeof selectedKey === "string" && selectedKey) return selectedKey;
  }

  throw new Error("No Supabase secret key is available to the Edge Function.");
}

function getRiyadhDate() {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Riyadh",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = Object.fromEntries(
    formatter.formatToParts(new Date()).map((part) => [part.type, part.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function dateToUtc(dateString) {
  const [year, month, day] = dateString.split("-").map(Number);
  return Date.UTC(year, month - 1, day);
}

function getExpiryState(expirationDate, today) {
  const daysLeft = Math.round(
    (dateToUtc(expirationDate) - dateToUtc(today)) / DAY_IN_MS,
  );

  if (daysLeft <= 0) return { daysLeft, status: EXPIRED };
  if (daysLeft <= 30) return { daysLeft, status: EXPIRES_SOON };
  return { daysLeft, status: ACTIVE };
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getRecipients(documentRecord) {
  const recipients = new Map();

  const addRecipient = (email, name) => {
    const normalizedEmail = String(email || "").trim().toLowerCase();
    if (!normalizedEmail || recipients.has(normalizedEmail)) return;
    recipients.set(normalizedEmail, {
      email: normalizedEmail,
      name: String(name || "").trim(),
    });
  };

  addRecipient(documentRecord.owner_email, documentRecord.owner_name);
  addRecipient(documentRecord.responsible_email, documentRecord.responsible_name);

  return [...recipients.values()];
}

function buildEmail(documentRecord, recipient, daysLeft, status, companyName) {
  const documentName = documentRecord.doc_name || "Document";
  const documentId = documentRecord.document_id || documentRecord.id;
  const greeting = recipient.name ? `Hello ${recipient.name},` : "Hello,";
  const dayWord = Math.abs(daysLeft) === 1 ? "day" : "days";

  const timingMessage = status === EXPIRED
    ? daysLeft === 0
      ? "The document expires today and is now marked as Expired."
      : `The document expired ${Math.abs(daysLeft)} ${dayWord} ago.`
    : `The document will expire in ${daysLeft} ${dayWord}.`;

  const subject = status === EXPIRED
    ? daysLeft === 0
      ? `Document Expires Today: ${documentName}`
      : `Document Expired (${Math.abs(daysLeft)} ${dayWord} ago): ${documentName}`
    : `Document Expiry Reminder (${daysLeft} ${dayWord} left): ${documentName}`;

  const text = [
    greeting,
    "",
    timingMessage,
    "",
    `Document: ${documentName}`,
    `Document ID: ${documentId}`,
    `Expiry Date: ${documentRecord.expiration_date}`,
    `Days Left: ${daysLeft}`,
    `Status: ${status}`,
    "",
    companyName,
  ].join("\n");

  const html = `
    <div style="font-family:Arial,sans-serif;max-width:620px;margin:auto;color:#1f2937;">
      <h2 style="margin-bottom:8px;">Document Expiry Notice</h2>
      <p>${escapeHtml(greeting)}</p>
      <p>${escapeHtml(timingMessage)}</p>
      <table style="width:100%;border-collapse:collapse;margin:20px 0;">
        <tr><td style="padding:8px;border:1px solid #e5e7eb;"><strong>Document</strong></td><td style="padding:8px;border:1px solid #e5e7eb;">${escapeHtml(documentName)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb;"><strong>Document ID</strong></td><td style="padding:8px;border:1px solid #e5e7eb;">${escapeHtml(documentId)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb;"><strong>Expiry Date</strong></td><td style="padding:8px;border:1px solid #e5e7eb;">${escapeHtml(documentRecord.expiration_date)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb;"><strong>Days Left</strong></td><td style="padding:8px;border:1px solid #e5e7eb;">${daysLeft}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb;"><strong>Status</strong></td><td style="padding:8px;border:1px solid #e5e7eb;">${escapeHtml(status)}</td></tr>
      </table>
      <p style="color:#6b7280;font-size:13px;">This is an automated message from ${escapeHtml(companyName)}.</p>
    </div>
  `;

  return { subject, text, html };
}

async function createIdempotencyKey(documentRecord, recipientEmail, status) {
  const input = [
    documentRecord.id,
    documentRecord.expiration_date,
    status,
    recipientEmail,
  ].join("|");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(input),
  );
  const hash = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `document-expiry-${hash}`;
}

async function sendExpiryEmail(
  resendApiKey,
  fromEmail,
  documentRecord,
  recipient,
  daysLeft,
  status,
  companyName,
) {
  const email = buildEmail(
    documentRecord,
    recipient,
    daysLeft,
    status,
    companyName,
  );
  const idempotencyKey = await createIdempotencyKey(
    documentRecord,
    recipient.email,
    status,
  );

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [recipient.email],
      subject: email.subject,
      text: email.text,
      html: email.html,
    }),
  });

  const result = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(
      `Email provider returned ${response.status}: ${result.message || "Unknown error"}`,
    );
  }

  return result.id || null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const cronSecret = requiredEnv("DOCUMENT_EXPIRY_CRON_SECRET");
    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const supabaseAdmin = createClient(supabaseUrl, getSupabaseAdminKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const isCronRequest = request.headers.get("x-cron-secret") === cronSecret;
    let requestedDocumentId = null;
    let callerUserId = null;

    if (!isCronRequest) {
      const authorization = request.headers.get("authorization") || "";
      const accessToken = authorization.startsWith("Bearer ")
        ? authorization.slice(7).trim()
        : "";
      if (!accessToken) {
        return jsonResponse({ error: "Unauthorized" }, 401);
      }

      const { data: authData, error: authError } =
        await supabaseAdmin.auth.getUser(accessToken);
      callerUserId = authData.user?.id || null;
      if (authError || !callerUserId) {
        return jsonResponse({ error: "Your session is no longer valid" }, 401);
      }

      const requestBody = await request.json().catch(() => null);
      requestedDocumentId = requestBody?.documentId;
      if (!isUuid(requestedDocumentId)) {
        return jsonResponse({ error: "A valid document is required" }, 400);
      }
    }

    const resendApiKey = requiredEnv("RESEND_API_KEY");
    const fromEmail = requiredEnv("DOCUMENT_EXPIRY_FROM_EMAIL");
    const companyName =
      Deno.env.get("DOCUMENT_EXPIRY_COMPANY_NAME") || "MUQAM HR";

    const documentFields =
      "id, document_id, employee_id, doc_name, owner_name, owner_email, responsible_name, responsible_email, expiration_date, status, last_notification_status, last_notified_at";
    let documents;
    let documentsError;

    if (isCronRequest) {
      const result = await supabaseAdmin
        .from("employee_documents")
        .select(documentFields)
        .not("expiration_date", "is", null);
      documents = result.data || [];
      documentsError = result.error;
    } else {
      const result = await supabaseAdmin
        .from("employee_documents")
        .select(documentFields)
        .eq("id", requestedDocumentId)
        .eq("employee_id", callerUserId)
        .maybeSingle();
      documents = result.data ? [result.data] : [];
      documentsError = result.error;

      if (!documentsError && documents.length === 0) {
        return jsonResponse({ error: "Document not found" }, 404);
      }
    }

    if (documentsError) throw documentsError;

    const today = getRiyadhDate();
    const summary = {
      date: today,
      processed: 0,
      statusesUpdated: 0,
      emailsSent: 0,
      failures: 0,
      errors: [],
    };

    for (const documentRecord of documents || []) {
      summary.processed += 1;

      try {
        const { daysLeft, status } = getExpiryState(
          documentRecord.expiration_date,
          today,
        );

        if (status === ACTIVE) {
          if (
            documentRecord.status !== ACTIVE ||
            documentRecord.last_notification_status !== null
          ) {
            const { error: resetError } = await supabaseAdmin
              .from("employee_documents")
              .update({
                status: ACTIVE,
                last_notification_status: null,
                last_notified_at: null,
                last_notification_error: null,
              })
              .eq("id", documentRecord.id);
            if (resetError) throw resetError;
            summary.statusesUpdated += 1;
          }
          continue;
        }

        if (documentRecord.status !== status) {
          const { error: statusError } = await supabaseAdmin
            .from("employee_documents")
            .update({ status })
            .eq("id", documentRecord.id);
          if (statusError) throw statusError;
          summary.statusesUpdated += 1;
        }

        const recipients = getRecipients(documentRecord);
        if (recipients.length === 0) {
          const message = "No owner or responsible email is available.";
          await supabaseAdmin
            .from("employee_documents")
            .update({ last_notification_error: message })
            .eq("id", documentRecord.id);
          summary.failures += 1;
          summary.errors.push({
            documentId: documentRecord.document_id || documentRecord.id,
            error: message,
          });
          continue;
        }

        let allDelivered = true;
        const deliveryErrors = [];

        for (const recipient of recipients) {
          const { data: existingNotification, error: lookupError } =
            await supabaseAdmin
              .from("document_expiry_notifications")
              .select("sent_at")
              .eq("employee_document_id", documentRecord.id)
              .eq("notification_status", status)
              .eq("recipient_email", recipient.email)
              .eq("expiration_date", documentRecord.expiration_date)
              .maybeSingle();

          if (lookupError) throw lookupError;
          if (existingNotification?.sent_at) continue;

          try {
            const providerMessageId = await sendExpiryEmail(
              resendApiKey,
              fromEmail,
              documentRecord,
              recipient,
              daysLeft,
              status,
              companyName,
            );

            const { error: notificationError } = await supabaseAdmin
              .from("document_expiry_notifications")
              .upsert(
                {
                  employee_document_id: documentRecord.id,
                  notification_status: status,
                  recipient_email: recipient.email,
                  expiration_date: documentRecord.expiration_date,
                  days_left: daysLeft,
                  sent_at: new Date().toISOString(),
                  provider_message_id: providerMessageId,
                  error_message: null,
                  updated_at: new Date().toISOString(),
                },
                {
                  onConflict:
                    "employee_document_id,notification_status,recipient_email,expiration_date",
                },
              );
            if (notificationError) throw notificationError;
            summary.emailsSent += 1;
          } catch (error) {
            allDelivered = false;
            summary.failures += 1;
            const message = String(error?.message || error).slice(0, 1000);
            deliveryErrors.push(message);

            await supabaseAdmin
              .from("document_expiry_notifications")
              .upsert(
                {
                  employee_document_id: documentRecord.id,
                  notification_status: status,
                  recipient_email: recipient.email,
                  expiration_date: documentRecord.expiration_date,
                  days_left: daysLeft,
                  error_message: message,
                  updated_at: new Date().toISOString(),
                },
                {
                  onConflict:
                    "employee_document_id,notification_status,recipient_email,expiration_date",
                },
              );
          }
        }

        const documentUpdate = {
          status,
          last_notification_error:
            deliveryErrors.length > 0 ? deliveryErrors.join(" | ") : null,
        };

        if (allDelivered) {
          documentUpdate.last_notification_status = status;
          documentUpdate.last_notified_at = new Date().toISOString();
        }

        const { error: finalUpdateError } = await supabaseAdmin
          .from("employee_documents")
          .update(documentUpdate)
          .eq("id", documentRecord.id);
        if (finalUpdateError) throw finalUpdateError;
      } catch (error) {
        summary.failures += 1;
        summary.errors.push({
          documentId: documentRecord.document_id || documentRecord.id,
          error: String(error?.message || error).slice(0, 1000),
        });
      }
    }

    return jsonResponse(summary, summary.failures > 0 ? 207 : 200);
  } catch (error) {
    console.error("Document expiry notification failed:", error);
    return jsonResponse({ error: "Unable to process document notifications" }, 500);
  }
});
