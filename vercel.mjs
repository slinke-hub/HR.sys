const connectSources = 'https://bbbetcdioiaozdjkvwxu.supabase.co wss://bbbetcdioiaozdjkvwxu.supabase.co https://jcfyyxsuspukcmybyhjj.supabase.co wss://jcfyyxsuspukcmybyhjj.supabase.co https://api.rss2json.com';

const securityHeaders = {
  'Content-Security-Policy': `default-src 'self'; base-uri 'self'; object-src 'none'; form-action 'self'; frame-ancestors 'none'; frame-src 'self' blob: https://vercel.live; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://vercel.live; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' data: https://fonts.gstatic.com; img-src 'self' data: blob: https:; media-src 'self' data: blob: https:; connect-src 'self' ${connectSources}; worker-src 'self' blob:; manifest-src 'self'; upgrade-insecure-requests`,
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(self), geolocation=(self), microphone=(), payment=(), usb=()',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'Origin-Agent-Cluster': '?1',
  'X-Permitted-Cross-Domain-Policies': 'none',
};

export const config = {
  buildCommand: 'node scripts/build-vercel.mjs',
  outputDirectory: 'www-vercel',
  routes: [
    {
      src: '/(.*)',
      headers: securityHeaders,
      continue: true,
    },
    {
      src: '/sw.js',
      headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' },
      continue: true,
    },
    {
      src: '/index.html',
      headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' },
      continue: true,
    },
  ],
};
