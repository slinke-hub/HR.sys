/* eslint-env node */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { inspectSecureLoginPublicKey, isAllowedSecureLoginPublicKey } = require('../supabase/functions/_shared/secure-login-public-key.mjs');

const root = path.resolve(__dirname, '..');
const edge = fs.readFileSync(path.join(root, 'supabase/functions/secure-login/index.ts'), 'utf8');
const originHelper = fs.readFileSync(path.join(root, 'supabase/functions/_shared/secure-login-origin.mjs'), 'utf8');

const stagingLegacyAnon = 'legacy-staging-anon-jwt';
const stagingPublishable = 'sb_publishable_staging-default';
const rotatedStagingPublishable = 'sb_publishable_staging-rotated';
const productionPublishable = 'sb_publishable_production-only';
const serviceRole = 'legacy-staging-service-role';
const publishableKeys = JSON.stringify({ default: stagingPublishable, reporting: rotatedStagingPublishable });
const options = { legacyAnonKey: stagingLegacyAnon, publishableKeysJson: publishableKeys, serviceRoleKey: serviceRole };

assert.equal(isAllowedSecureLoginPublicKey(stagingLegacyAnon, options), true, 'configured legacy anon key remains accepted');
assert.equal(isAllowedSecureLoginPublicKey(stagingPublishable, options), true, 'runtime-injected staging publishable key is accepted');
assert.equal(isAllowedSecureLoginPublicKey(rotatedStagingPublishable, options), true, 'other named staging publishable key is accepted');
assert.equal(isAllowedSecureLoginPublicKey(productionPublishable, options), false, 'a key absent from this project runtime allowlist is rejected');
assert.equal(isAllowedSecureLoginPublicKey('arbitrary-key', options), false, 'arbitrary credentials are rejected');
assert.equal(isAllowedSecureLoginPublicKey(serviceRole, options), false, 'legacy service-role credential is explicitly rejected');
assert.equal(isAllowedSecureLoginPublicKey('sb_secret_staging-secret', options), false, 'modern secret-key format is rejected');
assert.equal(isAllowedSecureLoginPublicKey(stagingPublishable, { ...options, publishableKeysJson: '{broken' }), false, 'malformed runtime map fails closed');
assert.equal(isAllowedSecureLoginPublicKey(stagingLegacyAnon, { ...options, publishableKeysJson: '{broken' }), true, 'valid legacy anon fallback remains available');
assert.equal(isAllowedSecureLoginPublicKey(serviceRole, { ...options, publishableKeysJson: JSON.stringify({ accidental: serviceRole }) }), false, 'service-role value cannot be enabled through a malformed allowlist configuration');
assert.equal(isAllowedSecureLoginPublicKey(null, options), false, 'missing apikey is rejected');

assert.deepEqual(
  (({ allowed, rejectionCategory, ...diagnostics }) => ({ allowed, rejectionCategory, ...diagnostics }))(
    inspectSecureLoginPublicKey(stagingPublishable, options),
  ),
  {
    allowed: true,
    rejectionCategory: null,
    hasLegacyAnon: true,
    hasPublishableKeys: true,
    runtimeValueShape: 'JSON_OBJECT',
    parsedPublicKeyCount: 2,
    requestMatchesRuntimeLegacyAnon: false,
    requestMatchesRuntimePublishableKey: true,
  },
  'valid object-map runtime configuration reports only safe shape/count metadata',
);
assert.deepEqual(
  inspectSecureLoginPublicKey(stagingLegacyAnon, options),
  {
    allowed: true,
    rejectionCategory: null,
    hasLegacyAnon: true,
    hasPublishableKeys: true,
    runtimeValueShape: 'JSON_OBJECT',
    parsedPublicKeyCount: 2,
    requestMatchesRuntimeLegacyAnon: true,
    requestMatchesRuntimePublishableKey: false,
  },
  'legacy anon candidate is matched only against the runtime legacy anon credential',
);
assert.deepEqual(
  inspectSecureLoginPublicKey('unrelated-candidate', options),
  {
    allowed: false,
    rejectionCategory: 'PUBLIC_KEY_REJECTED',
    hasLegacyAnon: true,
    hasPublishableKeys: true,
    runtimeValueShape: 'JSON_OBJECT',
    parsedPublicKeyCount: 2,
    requestMatchesRuntimeLegacyAnon: false,
    requestMatchesRuntimePublishableKey: false,
  },
  'unrelated candidate does not match either runtime public credential',
);
assert.equal(inspectSecureLoginPublicKey(stagingPublishable, { ...options, publishableKeysJson: '' }).runtimeValueShape, 'MISSING');
assert.equal(inspectSecureLoginPublicKey(stagingPublishable, { ...options, publishableKeysJson: '["sb_publishable_staging-default"]' }).runtimeValueShape, 'JSON_ARRAY');
assert.equal(inspectSecureLoginPublicKey(stagingPublishable, { ...options, publishableKeysJson: '"sb_publishable_staging-default"' }).runtimeValueShape, 'JSON_SCALAR');
assert.equal(inspectSecureLoginPublicKey(stagingPublishable, { ...options, publishableKeysJson: '{broken' }).runtimeValueShape, 'INVALID_JSON');
assert.equal(inspectSecureLoginPublicKey(serviceRole, options).rejectionCategory, 'SERVICE_ROLE_KEY_REJECTED');
assert.equal(inspectSecureLoginPublicKey('sb_secret_untrusted', options).rejectionCategory, 'PRIVILEGED_KEY_REJECTED');
assert.equal(inspectSecureLoginPublicKey('arbitrary-key', options).rejectionCategory, 'PUBLIC_KEY_REJECTED');

const diagnosticOutput = JSON.stringify(inspectSecureLoginPublicKey('unrelated-candidate', options));
for (const secret of [stagingLegacyAnon, stagingPublishable, rotatedStagingPublishable, serviceRole, 'sb_secret_untrusted', 'unrelated-candidate']) {
  assert.equal(diagnosticOutput.includes(secret), false, 'diagnostic output does not contain credential material');
}

assert.match(edge, /isAllowedSecureLoginOrigin\(origin, Deno\.env\.get\("HR_SYS_VERCEL_PREVIEW_ORIGIN"\)\)/, 'exact Origin validation remains in place');
assert.match(edge, /inspectSecureLoginPublicKey\(candidate,\s*\{\s*legacyAnonKey: anonKey,\s*publishableKeysJson,\s*serviceRoleKey/s, 'only trusted runtime public-key sources are used');
assert.match(edge, /if \(supabaseUrl === "https:\/\/jcfyyxsuspukcmybyhjj\.supabase\.co"\)/, 'diagnostics are guarded to the staging project URL');
assert.match(edge, /console\.warn\("secure-login public-key rejection", \{[\s\S]*rejectionCategory: publicKeyCheck\.rejectionCategory,[\s\S]*requestMatchesRuntimeLegacyAnon: publicKeyCheck\.requestMatchesRuntimeLegacyAnon,[\s\S]*requestMatchesRuntimePublishableKey: publicKeyCheck\.requestMatchesRuntimePublishableKey,[\s\S]*\}\);/, 'only fixed rejection metadata is logged');
assert.match(edge, /if \(request\.headers\.has\("Origin"\) && !origin\)\s*\{\s*return jsonResponse\(\{ error: "REQUEST_REJECTED" \}, 403, null\)/);
const rejectedKeyDiagnosticBlock = edge.match(/if \(!publicKeyCheck\.allowed\) \{([\s\S]*?return jsonResponse\(\{ error: "REQUEST_REJECTED" \}, 403, origin\);)/)?.[1] || '';
assert.match(rejectedKeyDiagnosticBlock, /return jsonResponse\(\{ error: "REQUEST_REJECTED" \}, 403, origin\);/i, 'rejected public keys retain the existing 403 response');
const diagnosticLogObject = edge.match(/console\.warn\("secure-login public-key rejection", \{([\s\S]*?)\}\);/)?.[1] || '';
assert.doesNotMatch(edge, /console\.(?:log|info|error)\s*\(/, 'diagnostics use only the guarded warning path');
assert.doesNotMatch(diagnosticLogObject, /candidate|apikey|anonKey|publishableKeysJson|serviceRoleKey|Origin|email|password|token|session|headers/i, 'diagnostic output excludes credential and request material');
assert.doesNotMatch(edge, /jsonResponse\(\{[^}]*\b(?:anonKey|publishableKeysJson|serviceRoleKey|apikey|RUNTIME_VALUE_SHAPE|PARSED_PUBLIC_KEY_COUNT)\b/i, 'key material and diagnostics are never returned');
assert.doesNotMatch(edge, /jsonResponse\([^\n]*(?:anonKey|publishableKeysJson|serviceRoleKey|apikey)/i, 'key material is never included in responses');
assert.match(originHelper, /export function isAllowedSecureLoginOrigin/, 'Origin boundary remains independently enforced');
assert.match(edge, /verify_jwt is disabled only because this endpoint precedes authentication/);

console.log('secure-login trusted public-key allowlist checks passed.');
