// Draft only. The caller's current JWT authorizes each request; no signed URL
// or privileged credential is returned to the browser.
const HEADERS = {
  'Cache-Control': 'private, no-store, max-age=0',
  'Pragma': 'no-cache',
  'X-Content-Type-Options': 'nosniff',
  'Content-Type': 'application/octet-stream',
  'Content-Disposition': 'attachment; filename="approval-document"',
};
// Preview origins must be explicitly configured for that environment. Local
// origins are accepted only when the deployment is explicitly development.
const cors = (request: Request) => {
  const origin = request.headers.get('origin') || '';
  const environment = Deno.env.get('APPROVAL_ENVIRONMENT') || '';
  const preview = Deno.env.get('APPROVAL_PREVIEW_ORIGIN') || '';
  let allowed = origin === 'https://sys.muqam.net';
  try {
    const u = new URL(origin);
    const exactOrigin = u.origin === origin && !u.username && !u.password;
    if (environment === 'preview' && exactOrigin && u.protocol === 'https:' && origin === preview) allowed = true;
    if (environment === 'development' && exactOrigin && ['localhost','127.0.0.1'].includes(u.hostname)
        && ['http:','https:'].includes(u.protocol)) allowed = true;
  } catch { /* no valid origin */ }
  return allowed ? { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Vary': 'Origin' } : {};
};
const noFile = (request: Request) => new Response('Document unavailable', { status: 404, headers: { ...HEADERS,...cors(request) } });
const isSafePath = (s: string) => s.length > 0 && s.length <= 1024 && !s.startsWith('/') && !s.includes('..') && !s.includes('\\');

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: { ...HEADERS,...cors(request) } });
  if (request.method !== 'POST') return noFile(request);
  const auth = request.headers.get('authorization') || '';
  if (!/^Bearer\s+\S+$/i.test(auth)) return noFile(request);
  const url = Deno.env.get('SUPABASE_URL') || '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') || '';
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SUPABASE_SECRET_KEY') || '';
  if (!url || !anon || !service) return noFile(request);
  const body = await request.json().catch(() => null);
  const id = body?.document_id;
  const source = body?.source;
  if (typeof id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id) || !['DEAL','DESIGN'].includes(source)) return noFile(request);
  try {
  const user = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anon, authorization: auth } });
  if (!user.ok) return noFile(request);
  const lookup = await fetch(`${url}/rest/v1/rpc/get_my_pending_crm_approval_document`, {
    method: 'POST', headers: { apikey: anon, authorization: auth, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_document_id: id, p_source: source }),
  });
  if (!lookup.ok) return noFile(request);
  const record = await lookup.json().catch(() => null);
  if (!record || record.id !== id || record.source !== source || typeof record.file_url !== 'string') return noFile(request);
  const bucket = source === 'DEAL' ? 'crm-deal-files' : 'task-attachments';
  const prefix = `storage://${bucket}/`;
  if (!record.file_url.startsWith(prefix)) return noFile(request);
  const objectPath = record.file_url.slice(prefix.length);
  if (!isSafePath(objectPath)) return noFile(request);
  const encodedPath = objectPath.split('/').map(encodeURIComponent).join('/');
  const file = await fetch(`${url}/storage/v1/object/authenticated/${bucket}/${encodedPath}`, {
    headers: { apikey: service, authorization: `Bearer ${service}` },
  });
  if (!file.ok || !file.body) return noFile(request);
  return new Response(file.body, { status: 200, headers: { ...HEADERS,...cors(request) } });
  } catch { return noFile(request); }
});
