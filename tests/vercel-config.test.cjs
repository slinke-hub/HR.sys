const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');

(async () => {
  const moduleUrl = new URL('../vercel.mjs?static=1', pathToFileURL(__filename));
  const config = (await import(moduleUrl.href)).config;
  assert.equal(config.buildCommand, 'node scripts/build-vercel.mjs');
  assert.equal(config.outputDirectory, 'www-vercel');
  const csp = config.headers[0].headers.find(({ key }) => key === 'Content-Security-Policy').value;
  assert.match(csp, /bbbetcdioiaozdjkvwxu\.supabase\.co/);
  assert.match(csp, /jcfyyxsuspukcmybyhjj\.supabase\.co/);
  assert.doesNotMatch(config.buildCommand, /VERCEL_ENV/);
  assert.doesNotMatch(config.outputDirectory, /VERCEL_ENV/);
  console.log('Static Vercel configuration checks passed.');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
