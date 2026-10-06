import { createClient } from "npm:@supabase/supabase-js@2";
import { isAllowedSecureLoginOrigin } from "../_shared/secure-login-origin.mjs";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const genericFailure = (origin: string | null) => jsonResponse({ error: "INVALID_CREDENTIALS" }, 401, origin);
const serviceUnavailable = (origin: string | null) => jsonResponse({ error: "AUTH_SERVICE_UNAVAILABLE" }, 503, origin);

function allowedOrigin(request: Request): string | null {
  const origin = request.headers.get("Origin");
  return isAllowedSecureLoginOrigin(origin, Deno.env.get("HR_SYS_VERCEL_PREVIEW_ORIGIN")) ? origin : null;
}

function responseHeaders(origin: string | null): Headers {
  const headers = new Headers({ "Content-Type": "application/json", "Cache-Control": "no-store", "Vary": "Origin" });
  if (origin) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Headers", "apikey, content-type, x-client-info");
    headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  }
  return headers;
}

function jsonResponse(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), { status, headers: responseHeaders(origin) });
}

Deno.serve(async (request: Request) => {
  const origin = allowedOrigin(request);
  if (request.headers.has("Origin") && !origin) return jsonResponse({ error: "REQUEST_REJECTED" }, 403, null);
  if (request.method === "OPTIONS") {
    return origin
      ? new Response(null, { status: 204, headers: responseHeaders(origin) })
      : jsonResponse({ error: "REQUEST_REJECTED" }, 403, null);
  }
  if (request.method !== "POST" || !supabaseUrl || !anonKey || !serviceRoleKey) return serviceUnavailable(origin);

  // verify_jwt is disabled only because this endpoint precedes authentication.
  // The project anon key is public and required; privileged work stays server-side.
  if (request.headers.get("apikey") !== anonKey) return jsonResponse({ error: "REQUEST_REJECTED" }, 403, origin);

  let input: { email?: unknown; password?: unknown };
  try {
    const rawBody = await request.text();
    if (new TextEncoder().encode(rawBody).byteLength > 8192) return jsonResponse({ error: "REQUEST_REJECTED" }, 413, origin);
    input = JSON.parse(rawBody);
  } catch (_) {
    return jsonResponse({ error: "REQUEST_REJECTED" }, 400, origin);
  }
  const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
  const password = typeof input.password === "string" ? input.password : "";
  if (email.length < 3 || email.length > 320 || !email.includes("@") || password.length < 1 || password.length > 1024) {
    return genericFailure(origin);
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  const trustedClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });

  try {
    // S3 intentionally denies browser reads. Enforce the existing 3-failure /
    // 24-hour lockout contract through this server-only read before Auth.
    const { data: lockout, error: lockoutError } = await trustedClient
      .from("login_attempts")
      .select("locked_until")
      .eq("email", email)
      .maybeSingle();
    if (lockoutError) return serviceUnavailable(origin);
    if (lockout?.locked_until && new Date(lockout.locked_until).getTime() > Date.now()) return genericFailure(origin);

    const { data, error } = await authClient.auth.signInWithPassword({ email, password });
    if (error || !data?.session) {
      // Count only a real invalid-credential response; throttles/outages do not
      // mutate lockout state. Recording is best-effort and silent on failure.
      const invalidCredentials = error?.status === 400
        && (error?.code === "invalid_credentials" || error?.message === "Invalid login credentials");
      if (invalidCredentials) {
        try { await trustedClient.rpc("record_failed_login", { user_email: email }); } catch (_) { /* best effort */ }
        return genericFailure(origin);
      }
      if (error?.status === 400) return genericFailure(origin);
      return serviceUnavailable(origin);
    }

    const session = data.session;
    return jsonResponse({ session: { access_token: session.access_token, refresh_token: session.refresh_token } }, 200, origin);
  } catch (_) {
    // Never log or return upstream errors, request values, or server credentials.
    return serviceUnavailable(origin);
  }
});
