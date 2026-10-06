const PRODUCTION_ORIGIN = 'https://sys.muqam.net';
const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1']);
const LOCAL_PROTOCOLS = new Set(['http:', 'https:']);

function parseExactPreviewOrigin(value) {
  const candidate = String(value || '').trim();
  if (!candidate || candidate.includes('*')) return null;

  try {
    const parsed = new URL(candidate);
    const hostname = parsed.hostname.toLowerCase();
    const isHrSysBranchPreview = hostname.startsWith('hr-sys-git-')
      && hostname.endsWith('.vercel.app');
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port
      || parsed.pathname !== '/' || parsed.search || parsed.hash
      || parsed.origin !== candidate || !isHrSysBranchPreview) return null;
    return parsed.origin;
  } catch (_) {
    return null;
  }
}

export function isAllowedSecureLoginOrigin(origin, configuredPreviewOrigin = '') {
  if (typeof origin !== 'string' || !origin) return false;
  if (origin === PRODUCTION_ORIGIN || origin === 'capacitor://localhost') return true;

  try {
    const parsed = new URL(origin);
    if (LOCAL_HOSTS.has(parsed.hostname.toLowerCase())
      && LOCAL_PROTOCOLS.has(parsed.protocol)
      && parsed.origin === origin
      && !parsed.username && !parsed.password
      && parsed.pathname === '/' && !parsed.search && !parsed.hash) return true;
  } catch (_) {
    return false;
  }

  return parseExactPreviewOrigin(configuredPreviewOrigin) === origin;
}
