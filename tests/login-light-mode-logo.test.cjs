const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const app = read('js/app.js');
const layout = read('css/layout.css');
const worker = read('sw.js');
const lightLogo = fs.readFileSync(path.join(root, 'images/login-logo-light.jpg'));
const darkLogo = fs.readFileSync(path.join(root, 'images/logo-dark.png'));

assert.equal(
  crypto.createHash('sha256').update(lightLogo).digest('hex').toUpperCase(),
  'F9CE313F50D13FEF0614A91C82882104E12FBD99659233900635271F2B57B702',
  'The repository asset must remain byte-for-byte identical to the supplied JPEG',
);
assert.match(app, /src="\/images\/login-logo-light\.jpg\?v=2026100801"[^>]*class="login-logo login-logo-light-mode"/,
  'Login markup uses the supplied image for the light-mode logo');
assert.match(app, /src="\/images\/logo-dark\.png\?v=20260906"[^>]*class="login-logo login-logo-dark-mode"/,
  'Login markup keeps the existing dark-mode logo asset unchanged');
assert.equal((app.match(/\$\{loginLogoHTML\}/g) || []).length, 3,
  'Sign-in, forgot-password, and reset-password screens share the same theme-aware logo markup');
assert.match(layout, /\.login-logo\s*\{[\s\S]*?height:\s*auto;[\s\S]*?object-fit:\s*contain;/,
  'Login logos preserve their source aspect ratios without cropping');
assert.match(layout, /\.login-logo-light-mode\s*\{[\s\S]*?width:\s*min\(320px, 100%\);/,
  'Light logo has a bounded responsive desktop size');
assert.match(layout, /@media \(max-width:\s*767px\)[\s\S]*?\.login-logo-light-mode\s*\{[\s\S]*?width:\s*min\(280px, 100%\);/,
  'Light logo has a bounded responsive mobile size');
assert.match(layout, /html\[data-theme="dark"\] \.login-logo-light-mode\s*\{\s*display:\s*none;/,
  'Light logo is hidden in dark mode');
assert.match(layout, /html\[data-theme="dark"\] \.login-logo-dark-mode\s*\{\s*display:\s*block;/,
  'Existing dark logo is displayed in dark mode');
assert.match(worker, /'\/images\/login-logo-light\.jpg'/,
  'The supplied logo is included in the offline application shell');
assert.match(html, /css\/layout\.css\?v=2026100801/, 'Layout cache key is refreshed');
assert.match(html, /js\/app\.js\?v=2026100801/, 'Application cache key is refreshed');

const css = [...html.matchAll(/<link\s+rel="stylesheet"\s+href="([^"]+)"/g)]
  .map(([, href]) => href.split('?')[0])
  .filter((href) => href.startsWith('css/'))
  .map(read)
  .join('\n');
const lightData = `data:image/jpeg;base64,${lightLogo.toString('base64')}`;
const darkData = `data:image/png;base64,${darkLogo.toString('base64')}`;

function markup(theme) {
  return `<!doctype html><html data-theme="${theme}" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:0}${css}</style></head><body>
    <div class="login-screen-shell">
      <div class="card login-card-wrapper">
        <div style="text-align:center;margin-bottom:2rem">
          <div class="logo login-logo-container">
            <img src="${lightData}" alt="MUQAM HR Logo" class="login-logo login-logo-light-mode">
            <img src="${darkData}" alt="MUQAM HR Logo" class="login-logo login-logo-dark-mode">
          </div>
          <h2>Login</h2>
        </div>
      </div>
    </div>
  </body></html>`;
}

async function geometry(page) {
  return page.evaluate(() => {
    const frame = document.querySelector('.login-logo-container').getBoundingClientRect();
    const images = [...document.querySelectorAll('.login-logo')].map((image) => {
      const rect = image.getBoundingClientRect();
      return {
        className: image.className,
        display: getComputedStyle(image).display,
        width: rect.width,
        height: rect.height,
        centerX: rect.left + rect.width / 2,
        naturalWidth: image.naturalWidth,
        naturalHeight: image.naturalHeight,
      };
    });
    return {
      frameWidth: frame.width,
      frameCenterX: frame.left + frame.width / 2,
      images,
    };
  });
}

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    for (const width of [1440, 390]) {
      for (const theme of ['light', 'dark']) {
        await page.setViewport({ width, height: width < 500 ? 844 : 900 });
        await page.setContent(markup(theme), { waitUntil: 'load' });
        const result = await geometry(page);
        const visible = result.images.filter((image) => image.display !== 'none');
        assert.equal(visible.length, 1, `${theme} mode shows exactly one login logo at ${width}px`);
        const logo = visible[0];
        assert.ok(Math.abs(logo.centerX - result.frameCenterX) <= 1,
          `${theme} login logo remains centered at ${width}px`);
        assert.ok(logo.width <= result.frameWidth + 1,
          `${theme} login logo fits within its container at ${width}px`);
        if (theme === 'light') {
          assert.match(logo.className, /login-logo-light-mode/, 'Light mode shows the supplied JPEG');
          assert.equal(logo.naturalWidth, 2245, 'Supplied JPEG width is preserved');
          assert.equal(logo.naturalHeight, 1241, 'Supplied JPEG height is preserved');
          assert.ok(Math.abs((logo.width / logo.height) - (logo.naturalWidth / logo.naturalHeight)) < .01,
            `Light login logo preserves its original aspect ratio at ${width}px`);
          assert.ok(logo.width <= (width < 500 ? 280 : 320) + 1, 'Light logo respects its responsive size cap');
        } else {
          assert.match(logo.className, /login-logo-dark-mode/, 'Dark mode keeps the existing logo');
          assert.equal(logo.naturalWidth, 672, 'Existing dark logo source remains unchanged');
          assert.equal(logo.naturalHeight, 371, 'Existing dark logo source remains unchanged');
          assert.ok(logo.height <= 91, 'Dark logo keeps its existing 90px height cap');
        }
      }
    }
    console.log('Light-mode login logo rendered contract: PASS');
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
