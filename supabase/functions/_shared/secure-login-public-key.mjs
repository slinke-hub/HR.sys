function inspectPublishableKeys(rawValue) {
  if (typeof rawValue !== 'string' || !rawValue.trim()) {
    return { shape: 'MISSING', keys: [] };
  }
  try {
    const parsed = JSON.parse(rawValue);
    if (Array.isArray(parsed)) return { shape: 'JSON_ARRAY', keys: [] };
    if (!parsed || typeof parsed !== 'object') return { shape: 'JSON_SCALAR', keys: [] };
    return {
      shape: 'JSON_OBJECT',
      keys: Object.values(parsed).filter(value => typeof value === 'string' && value.startsWith('sb_publishable_')),
    };
  } catch (_) {
    return { shape: 'INVALID_JSON', keys: [] };
  }
}

export function inspectSecureLoginPublicKey(candidate, {
  legacyAnonKey = '',
  publishableKeysJson = '',
  serviceRoleKey = '',
} = {}) {
  const publishable = inspectPublishableKeys(publishableKeysJson);
  const diagnostics = {
    hasLegacyAnon: typeof legacyAnonKey === 'string' && legacyAnonKey.length > 0,
    hasPublishableKeys: typeof publishableKeysJson === 'string' && publishableKeysJson.length > 0,
    runtimeValueShape: publishable.shape,
    parsedPublicKeyCount: publishable.keys.length,
    requestMatchesRuntimeLegacyAnon: typeof candidate === 'string' && candidate.length > 0 && candidate === legacyAnonKey,
    requestMatchesRuntimePublishableKey: typeof candidate === 'string' && publishable.keys.includes(candidate),
  };

  if (typeof candidate !== 'string' || !candidate) {
    return { allowed: false, rejectionCategory: 'PUBLIC_KEY_REJECTED', ...diagnostics };
  }
  if (serviceRoleKey && candidate === serviceRoleKey) {
    return { allowed: false, rejectionCategory: 'SERVICE_ROLE_KEY_REJECTED', ...diagnostics };
  }
  if (candidate.startsWith('sb_secret_')) {
    return { allowed: false, rejectionCategory: 'PRIVILEGED_KEY_REJECTED', ...diagnostics };
  }

  const allowed = new Set();
  if (legacyAnonKey && legacyAnonKey !== serviceRoleKey && !legacyAnonKey.startsWith('sb_secret_')) {
    allowed.add(legacyAnonKey);
  }

  for (const key of publishable.keys) {
    if (key !== serviceRoleKey) allowed.add(key);
  }

  const isAllowed = allowed.has(candidate);
  return {
    allowed: isAllowed,
    rejectionCategory: isAllowed ? null : 'PUBLIC_KEY_REJECTED',
    ...diagnostics,
  };
}

export function isAllowedSecureLoginPublicKey(candidate, options = {}) {
  return inspectSecureLoginPublicKey(candidate, options).allowed;
}
