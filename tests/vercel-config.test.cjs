const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

(async () => {
  const moduleUrl = new URL('../vercel.mjs?static=1', pathToFileURL(__filename));
  const config = (await import(moduleUrl.href)).config;
  const projectRoot = path.join(__dirname, '..');
  assert.equal(config.buildCommand, 'node scripts/build-vercel.mjs');
  assert.equal(config.outputDirectory, 'www-vercel');
  assert.equal(config.git?.deploymentEnabled, undefined, 'Preview deployments must not be suppressed by branch configuration');
  for (const competingConfig of ['vercel.json', 'vercel.ts', 'vercel.js', 'vercel.cjs', 'vercel.mts']) {
    assert.equal(
      fs.existsSync(path.join(projectRoot, competingConfig)),
      false,
      `${competingConfig} must not compete with the sole vercel.mjs configuration`,
    );
  }
  assert.ok(Array.isArray(config.routes), 'Vercel response-header rules must use the route schema');
  assert.equal(config.headers, undefined, 'legacy nested headers config must not be emitted');
  for (const [routeIndex, route] of config.routes.entries()) {
    assert.equal(typeof route.src, 'string', `route ${routeIndex} must define src`);
    assert.equal(route.continue, true, `route ${routeIndex} must continue after applying response headers`);
    assert.ok(route.headers && !Array.isArray(route.headers), `route ${routeIndex} headers must be a key/value map`);
    for (const [key, value] of Object.entries(route.headers)) {
      assert.equal(typeof key, 'string');
      assert.notEqual(key, '');
      assert.equal(typeof value, 'string', `route ${routeIndex} header ${key} must have a string value`);
      assert.notEqual(value, '', `route ${routeIndex} header ${key} must not have a missing/empty value`);
    }
  }
  const securityRoute = config.routes.find(({ src }) => src === '/(.*)');
  assert.ok(securityRoute, 'security header route is required');
  const runtimeConfigRoute = config.routes.find(({ src }) => src === '/runtime-config.js');
  assert.ok(runtimeConfigRoute, 'runtime-config.js must have an explicit cache policy');
  assert.equal(runtimeConfigRoute.headers['Cache-Control'], 'no-store');
  assert.equal(runtimeConfigRoute.continue, true);
  const csp = securityRoute.headers['Content-Security-Policy'];
  assert.match(csp, /bbbetcdioiaozdjkvwxu\.supabase\.co/);
  assert.match(csp, /jcfyyxsuspukcmybyhjj\.supabase\.co/);
  assert.doesNotMatch(config.buildCommand, /VERCEL_ENV/);
  assert.doesNotMatch(config.outputDirectory, /VERCEL_ENV/);
  console.log('Static Vercel configuration checks passed.');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
