import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import { extname, resolve, sep } from 'node:path';

const host = '127.0.0.1';
const port = 4173;
const webRoot = resolve(import.meta.dirname, '..', 'www');
const contentSecurityPolicy = [
  "default-src 'self'",
  "base-uri 'self'",
  "object-src 'none'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "frame-src 'self' blob:",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' data: https://fonts.gstatic.com",
  "img-src 'self' data: blob: https:",
  "media-src 'self' data: blob: https:",
  "connect-src 'self' https://bbbetcdioiaozdjkvwxu.supabase.co wss://bbbetcdioiaozdjkvwxu.supabase.co",
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
  response.setHeader('Cache-Control', 'no-store');
}

function sendText(response, statusCode, message) {
  response.statusCode = statusCode;
  response.setHeader('Content-Type', 'text/plain; charset=utf-8');
  response.end(message);
}

const server = createServer(async (request, response) => {
  setSecurityHeaders(response);
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
    response.setHeader('Content-Length', fileStat.size);
    if (request.method === 'HEAD') {
      response.end();
      return;
    }
    createReadStream(filePath).on('error', () => {
      if (!response.headersSent) sendText(response, 500, 'Internal server error');
      else response.destroy();
    }).pipe(response);
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
