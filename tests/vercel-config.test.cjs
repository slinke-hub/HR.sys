const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');

(async () => {
  const moduleUrl = new URL('../vercel.mjs?static=1', pathToFileURL(__filename));
  const config = (await import(moduleUrl.href)).config;
  assert.equal(config.buildCommand, 'node scripts/build-vercel.mjs');
  assert.equal(config.outputDirectory, 'www-vercel');
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
