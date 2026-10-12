const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const html = read('index.html');
const app = read('js/app.js');
const components = read('css/components.css');
const header = html.match(/<header class="topbar"[\s\S]*?<\/header>/)?.[0];

assert.ok(header, 'Use the shared application header');
assert.match(html, /css\/components\.css\?v=2026100802/,
  'The updated dropdown positioning stylesheet has a fresh cache key');
assert.match(components, /\.profile-dropdown-wrapper \.profile-dropdown-menu\s*\{[\s\S]*?position:\s*fixed !important;[\s\S]*?top:\s*var\(--profile-dropdown-top,[\s\S]*?left:\s*var\(--profile-dropdown-left,[\s\S]*?right:\s*auto !important;/,
  'The profile menu uses trigger-relative runtime coordinates');
assert.match(app, /window\.positionProfileDropdown = function \(\)[\s\S]*?const preferredLeft = isRtl \? triggerRect\.right - dropdownWidth : triggerRect\.left;[\s\S]*?viewportWidth - dropdownWidth - margin/,
  'The profile menu aligns with the avatar side and clamps to the viewport');
assert.match(app, /if \(!isShowing\) window\.positionProfileDropdown\(\);/,
  'Opening the profile menu immediately positions it beneath the trigger');
assert.match(app, /window\.addEventListener\('resize', window\.positionProfileDropdown\);[\s\S]*?window\.visualViewport\?\.addEventListener\('scroll', window\.positionProfileDropdown\);/,
  'The open profile menu follows viewport resize and visual scrolling');

const css = [...html.matchAll(/<link\s+rel="stylesheet"\s+href="([^"]+)"/g)]
  .map(([, href]) => href.split('?')[0])
  .filter((href) => href.startsWith('css/'))
  .map(read)
  .join('\n');

function markup(direction) {
  return `<!doctype html><html dir="${direction}" data-theme="light"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:0}${css}</style></head><body>${header}</body></html>`;
}

const positionerStart = app.indexOf('window.positionProfileDropdown = function ()');
const positionerEnd = app.indexOf('\n};', positionerStart);
assert.ok(positionerStart >= 0 && positionerEnd > positionerStart, 'Profile dropdown positioner is defined');
const positioner = `${app.slice(positionerStart, positionerEnd + 3)};`;

async function geometry(page) {
  return page.evaluate(() => {
    const wrapper = document.querySelector('.profile-dropdown-wrapper').getBoundingClientRect();
    const avatar = document.querySelector('#topbarAvatar').getBoundingClientRect();
    const menuNode = document.querySelector('#profileDropdown');
    menuNode.style.display = 'block';
    const menu = menuNode.getBoundingClientRect();
    return {
      viewportWidth: window.innerWidth,
      wrapper: { left: wrapper.left, right: wrapper.right, bottom: wrapper.bottom },
      avatar: { left: avatar.left, right: avatar.right, bottom: avatar.bottom },
      menu: { left: menu.left, right: menu.right, top: menu.top, width: menu.width },
      position: getComputedStyle(menuNode).position,
    };
  });
}

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    for (const width of [1440, 1024, 768, 430, 390, 375]) {
      for (const direction of ['ltr', 'rtl']) {
        await page.setViewport({ width, height: width <= 430 ? 844 : 900 });
        await page.setContent(markup(direction));
        await page.addScriptTag({ content: positioner });
        await page.evaluate(() => {
          const menu = document.querySelector('#profileDropdown');
          menu.style.display = 'block';
          window.positionProfileDropdown();
        });
        const result = await geometry(page);
        assert.equal(result.position, 'fixed', `${direction} menu stays trigger-relative at ${width}px`);
        assert.ok(result.menu.top >= result.wrapper.bottom + 7 && result.menu.top <= result.wrapper.bottom + 9,
          `${direction} menu opens directly beneath the avatar at ${width}px`);
        if (direction === 'ltr') {
          assert.ok(result.menu.left <= result.wrapper.left + 1 && result.menu.right >= result.wrapper.left,
            `LTR menu stays beneath the left-side avatar at ${width}px`);
        } else {
          assert.ok(result.menu.right >= result.wrapper.right - 1 && result.menu.left <= result.wrapper.right,
            `RTL menu mirrors beneath its avatar at ${width}px`);
        }
        assert.ok(result.menu.left >= -1 && result.menu.right <= result.viewportWidth + 1,
          `${direction} menu remains inside the viewport at ${width}px: ${JSON.stringify(result)}`);
        assert.ok(result.menu.top > result.avatar.bottom,
          `${direction} menu does not cover the avatar at ${width}px`);
      }
    }
    console.log('Profile dropdown trigger-relative positioning: PASS');
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
