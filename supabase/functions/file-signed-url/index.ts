import { createClient } from "npm:@supabase/supabase-js@2";

const MAX_SIGNED_URL_TTL_SECONDS = 300;
const MIN_SIGNED_URL_TTL_SECONDS = 60;
const PRIVATE_BUCKETS = new Set([
  "task-attachments",
  "contract-documents",
  "crm-deal-files",
  "hr-documents",
]);

const allowedOrigins = (origin: string) => {
  if (origin === "https://sys.muqam.net") return true;
  try {
    const url = new URL(origin);
    return ["localhost", "127.0.0.1"].includes(url.hostname)
      && ["http:", "https:", "capacitor:"].includes(url.protocol);
  } catch (_) {
    return false;
  }
};

const corsHeaders = (request: Request) => {
  const origin = request.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": allowedOrigins(origin) ? origin : "https://sys.muqam.net",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Credentials": "true",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
};

const response = (request: Request, body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(request), "Content-Type": "application/json" },
  });

const validPath = (path: unknown) => {
  const value = String(path || "").trim();
  return value.length > 0 && value.length <= 1024 && !value.includes("..")
    && !value.includes("\\") && !value.startsWith("/");
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(request) });
  if (request.method !== "POST") return response(request, { error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY") || "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey) return response(request, { error: "Supabase service configuration is missing" }, 500);

  const authorization = request.headers.get("Authorization") || "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) return response(request, { error: "Authentication required" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) return response(request, { error: "Authentication required" }, 401);

  const input = await request.json().catch(() => ({}));
  const bucket = String(input?.bucket || "").trim();
  const path = String(input?.path || input?.storage_path || "").trim();
  if (!PRIVATE_BUCKETS.has(bucket) || !validPath(path)) return response(request, { error: "Invalid private file reference" }, 400);

  // The caller may request a shorter lifetime, but can never extend the server cap.
  const requested = Number(input?.expiresIn ?? input?.expires_in ?? MAX_SIGNED_URL_TTL_SECONDS);
  const expiresIn = Math.min(
    Math.max(Number.isFinite(requested) ? Math.floor(requested) : MAX_SIGNED_URL_TTL_SECONDS, MIN_SIGNED_URL_TTL_SECONDS),
    MAX_SIGNED_URL_TTL_SECONDS,
  );

  // Use the caller's JWT for Storage authorization. This preserves every existing
  // parent/RLS policy and prevents the service role from bypassing file ownership.
  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data, error } = await userClient.storage.from(bucket).createSignedUrl(path, expiresIn);
  if (error || !data?.signedUrl) return response(request, { error: "File is not accessible" }, 403);
  return response(request, { signedUrl: data.signedUrl, expiresIn, maxExpiresIn: MAX_SIGNED_URL_TTL_SECONDS });
});
