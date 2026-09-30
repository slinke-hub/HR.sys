const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');

async function loadConfig(environment) {
  const previous = process.env.VERCEL_ENV;
  if (environment === undefined) delete process.env.VERCEL_ENV;
  else process.env.VERCEL_ENV = environment;
  try {
    const moduleUrl = new URL(`../vercel.mjs?env=${encodeURIComponent(environment || 'unset')}`, pathToFileURL(__filename));
    return (await import(moduleUrl.href)).config;
  } finally {
    if (previous === undefined) delete process.env.VERCEL_ENV;
    else process.env.VERCEL_ENV = previous;
  }
}

(async () => {
  const production = await loadConfig('production');
  assert.equal(production.buildCommand, 'npm run mobile:web:production');
  assert.equal(production.outputDirectory, 'www-production');
  const productionCsp = production.headers[0].headers.find(({ key }) => key === 'Content-Security-Policy').value;
  assert.match(productionCsp, /bbbetcdioiaozdjkvwxu\.supabase\.co/);
  assert.doesNotMatch(productionCsp, /jcfyyxsuspukcmybyhjj\.supabase\.co/);

  const preview = await loadConfig('preview');
  assert.equal(preview.buildCommand, 'npm run mobile:web:preview');
  assert.equal(preview.outputDirectory, 'www');
  const previewCsp = preview.headers[0].headers.find(({ key }) => key === 'Content-Security-Policy').value;
  assert.match(previewCsp, /jcfyyxsuspukcmybyhjj\.supabase\.co/);

  console.log('Vercel environment configuration checks passed.');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
