import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createBrotliCompress, createGzip } from 'node:zlib';
import { extname, resolve, sep } from 'node:path';

const host = '127.0.0.1';
const port = Number(process.env.HR_SYS_PORT || 4173);
const webRoot = resolve(import.meta.dirname, '..', 'www');
const projectRoot = resolve(import.meta.dirname, '..');
const stagingRef = 'jcfyyxsuspukcmybyhjj';
const productionRef = 'bbbetcdioiaozdjkvwxu';

async function readLocalEnvFile() {
  try {
    const contents = await readFile(resolve(projectRoot, 'supabase/.env.staging.local'), 'utf8');
    return Object.fromEntries(contents.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#')).map(line => {
      const separator = line.indexOf('=');
      return separator < 0 ? [line, ''] : [line.slice(0, separator).trim(), line.slice(separator + 1).trim().replace(/^['"]|['"]$/g, '')];
    }));
  } catch (_) { return {}; }
}

function isStagingAnonKey(value) {
  try {
    const parts = String(value || '').split('.');
    if (parts.length !== 3) return false;
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return payload.ref === stagingRef && payload.role === 'anon';
  } catch (_) { return false; }
}

async function getRuntimeConfigScript() {
  const mode = String(process.env.HR_SYS_RUNTIME || 'production').trim().toLowerCase();
  if (mode !== 'staging') {
    return `window.HR_RUNTIME_CONFIG=${JSON.stringify({ mode: 'production', valid: true, projectRef: productionRef })};`;
  }
  const localEnv = await readLocalEnvFile();
  const anonKey = String(process.env.HR_SYS_STAGING_ANON_KEY || process.env.MUQAM_SUPABASE_ANON_KEY || localEnv.MUQAM_SUPABASE_ANON_KEY || '').trim();
  const valid = isStagingAnonKey(anonKey);
  const config = valid
    ? { mode: 'staging', valid: true, projectRef: stagingRef, supabaseUrl: `https://${stagingRef}.supabase.co`, anonKey }
    : { mode: 'staging', valid: false, projectRef: stagingRef, error: 'Missing or invalid staging public anon key. Add MUQAM_SUPABASE_ANON_KEY to supabase/.env.staging.local.' };
  return `window.HR_RUNTIME_CONFIG=${JSON.stringify(config)};`;
}
const contentSecurityPolicy = [
  "default-src 'self'",
  "base-uri 'self'",
  "object-src 'none'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "frame-src 'self' blob: https://vercel.live",
  "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://vercel.live",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' data: https://fonts.gstatic.com",
  "img-src 'self' data: blob: https:",
  "media-src 'self' data: blob: https:",
  "connect-src 'self' https://bbbetcdioiaozdjkvwxu.supabase.co wss://bbbetcdioiaozdjkvwxu.supabase.co https://jcfyyxsuspukcmybyhjj.supabase.co wss://jcfyyxsuspukcmybyhjj.supabase.co https://api.rss2json.com",
  "worker-src 'self' blob:",
  "manifest-src 'self'"
].join('; ');

const mimeTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.ico', 'image/x-icon'],
  ['.jpeg', 'image/jpeg'],
  ['.jpg', 'image/jpeg'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.mp3', 'audio/mpeg'],
  ['.mjs', 'text/javascript; charset=utf-8'],
  ['.ogg', 'audio/ogg'],
  ['.pdf', 'application/pdf'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.webp', 'image/webp'],
  ['.woff', 'font/woff'],
  ['.woff2', 'font/woff2']
]);

function setSecurityHeaders(response) {
  response.setHeader('Content-Security-Policy', contentSecurityPolicy);
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  response.setHeader('Permissions-Policy', 'camera=(self), geolocation=(self), microphone=(), payment=(), usb=()');
  response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  response.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
  response.setHeader('Origin-Agent-Cluster', '?1');
  response.setHeader('X-Permitted-Cross-Domain-Policies', 'none');
  // Keep HTML fresh while allowing immutable/versioned assets to be reused.
  // The app uses query-string versions for deploys, so caching these large
  // bundles avoids downloading them on every navigation or refresh.
  response.setHeader('Cache-Control', 'no-store');
}

function sendText(response, statusCode, message) {
  response.statusCode = statusCode;
  response.setHeader('Content-Type', 'text/plain; charset=utf-8');
  response.end(message);
}

const server = createServer(async (request, response) => {
  setSecurityHeaders(response);
  if (request.url === '/runtime-config.js') {
    response.statusCode = 200;
    response.setHeader('Content-Type', 'text/javascript; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store');
    response.end(await getRuntimeConfigScript());
    return;
  }
  if ((request.url || '').length > 4096) {
    sendText(response, 414, 'URI too long');
    return;
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.setHeader('Allow', 'GET, HEAD');
    sendText(response, 405, 'Method not allowed');
    return;
  }

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url || '/', `http://${host}:${port}`).pathname);
  } catch (_) {
    sendText(response, 400, 'Bad request');
    return;
  }

  if (pathname.includes('\0') || pathname.split('/').some(segment => segment.startsWith('.'))) {
    sendText(response, 404, 'Not found');
    return;
  }

  const requestedPath = pathname === '/' ? '/index.html' : pathname;
  const filePath = resolve(webRoot, `.${requestedPath}`);
  if (filePath !== webRoot && !filePath.startsWith(`${webRoot}${sep}`)) {
    sendText(response, 404, 'Not found');
    return;
  }

  try {
    const fileStat = await stat(filePath);
    if (!fileStat.isFile()) throw new Error('Not a file');
    response.statusCode = 200;
    response.setHeader('Content-Type', mimeTypes.get(extname(filePath).toLowerCase()) || 'application/octet-stream');
    const contentType = mimeTypes.get(extname(filePath).toLowerCase()) || 'application/octet-stream';
    const compressible = /^(text\/|application\/javascript|application\/json|image\/svg\+xml)/i.test(contentType);
    const acceptEncoding = String(request.headers['accept-encoding'] || '');
    let output = response;
    if (compressible && acceptEncoding.includes('br')) {
      response.setHeader('Content-Encoding', 'br');
      output = createBrotliCompress();
      output.pipe(response);
    } else if (compressible && acceptEncoding.includes('gzip')) {
      response.setHeader('Content-Encoding', 'gzip');
      output = createGzip();
      output.pipe(response);
    } else {
      response.setHeader('Content-Length', fileStat.size);
    }
    response.setHeader('Vary', 'Accept-Encoding');
    if (pathname !== '/' && pathname !== '/index.html' && extname(filePath).toLowerCase() !== '.html') {
      response.setHeader('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
    }
    if (request.method === 'HEAD') {
      response.end();
      return;
    }
    createReadStream(filePath).on('error', () => {
      if (!response.headersSent) sendText(response, 500, 'Internal server error');
      else response.destroy();
    }).pipe(output);
  } catch (_) {
    sendText(response, 404, 'Not found');
  }
});

server.listen(port, host, () => {
  console.log(`MUQAM HR local server: http://${host}:${port}`);
});

server.on('error', error => {
  console.error(`Unable to start the local server: ${error.message}`);
  process.exitCode = 1;
});
