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
assert.ok(header, 'Use the actual shared header markup from index.html');
const toggleStart = app.indexOf('window.toggleLanguage = function ()');
const toggleEnd = app.indexOf('\n};', toggleStart);
assert.ok(toggleStart >= 0 && toggleEnd > toggleStart, 'Application language toggle must be present');
assert.match(app.slice(toggleStart, toggleEnd), /htmlElement\.setAttribute\('dir', currentLang === 'ar' \? 'rtl' : 'ltr'\)/,
  'Language switch updates the document direction that controls header placement');
assert.match(components, /\.header-logo \.app-logo \{[^}]*max-width:\s*156px;[^}]*max-height:\s*45px;[^}]*width:\s*auto;[^}]*object-fit:\s*contain;/,
  'Desktop logo grows by about 18% while preserving its aspect ratio');
assert.match(components, /@media \(max-width:\s*1100px\)[\s\S]*?\.header-logo \.app-logo \{[^}]*max-width:\s*132px;[^}]*max-height:\s*40px;/,
  'Tablet logo keeps the same moderate proportional increase');
assert.match(components, /@media \(max-width:\s*380px\)[\s\S]*?\.header-logo \.app-logo \{[^}]*max-width:\s*104px;[^}]*max-height:\s*34px;/,
  'Small-phone logo remains balanced within the available header width');

// Load stylesheets in index.html order so late cascade overrides are tested
// exactly as they are in the rendered application.
const css = [...html.matchAll(/<link\s+rel="stylesheet"\s+href="([^"]+)"/g)]
  .map(([, href]) => href.split('?')[0])
  .filter((href) => href.startsWith('css/'))
  .map(read)
  .join('\n');
const testHeader = header
  .replace(/<img src="\/images\/logo\.png"[^>]*>/, '<img src="data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=" alt="MUQAM HR Logo" class="app-logo app-logo-light" width="120" height="36">')
  .replace(/<img src="\/images\/logo-dark\.png[^"]*"[^>]*>/, '<img src="data:image/gif;base64,R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=" alt="MUQAM HR Logo" class="app-logo app-logo-dark" width="120" height="36">');

function pageMarkup(direction, theme) {
  return `<!doctype html><html lang="${direction === 'rtl' ? 'ar' : 'en'}" dir="${direction}" data-theme="${theme}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:0}${css}</style></head><body>${testHeader}</body></html>`;
}

async function positions(page) {
  return page.evaluate(() => {
    const brand = document.querySelector('.header-brand-group').getBoundingClientRect();
    const actions = document.querySelector('.topbar-actions').getBoundingClientRect();
    const topbar = document.querySelector('.topbar');
    const bar = topbar.getBoundingClientRect();
    const logoNode = [...document.querySelectorAll('.header-logo .app-logo')]
      .find((node) => getComputedStyle(node).display !== 'none');
    const logoStyle = getComputedStyle(logoNode);
    return {
      width: window.innerWidth,
      clientWidth: document.documentElement.clientWidth,
      pageScrollWidth: document.documentElement.scrollWidth,
      barScrollWidth: topbar.scrollWidth,
      barClientWidth: topbar.clientWidth,
      barHeight: bar.height,
      barLeft: bar.left,
      barRight: bar.right,
      barPaddingLeft: parseFloat(getComputedStyle(topbar).paddingLeft),
      barPaddingRight: parseFloat(getComputedStyle(topbar).paddingRight),
      brandLeft: brand.left,
      brandRight: brand.right,
      brandWidth: brand.width,
      actionsLeft: actions.left,
      actionsRight: actions.right,
      actionsWidth: actions.width,
      brandCenterY: brand.top + brand.height / 2,
      actionsCenterY: actions.top + actions.height / 2,
      barCenterY: bar.top + bar.height / 2,
      logoHeight: logoNode.getBoundingClientRect().height,
      logoMaxHeight: parseFloat(logoStyle.maxHeight),
      logoObjectFit: logoStyle.objectFit,
      userInfoDisplay: getComputedStyle(document.querySelector('.user-info')).display,
      profileChevronDisplay: getComputedStyle(document.querySelector('.user-profile > svg, .user-profile > i')).display,
      actionChildren: [...document.querySelector('.topbar-actions').children].map((node) => node.className),
    };
  });
}

function assertDirection(layout, direction, width) {
  assert.equal(layout.width, width);
  assert.equal(layout.clientWidth, width, `${width}px CSS viewport is preserved`);
  assert.ok(layout.pageScrollWidth <= width + 1, `page has no horizontal overflow at ${width}px`);
  assert.ok(layout.barScrollWidth <= layout.barClientWidth + 1, `header groups fit without clipping at ${width}px`);
  const edgeTolerance = width <= 560 ? 14 : 10;
  const leftPaddingEdge = layout.barLeft + layout.barPaddingLeft;
  const rightPaddingEdge = layout.barRight - layout.barPaddingRight;
  if (direction === 'ltr') {
    assert.ok(Math.abs(layout.actionsLeft - leftPaddingEdge) <= edgeTolerance,
      `LTR utilities anchor to the header left padding at ${width}px (edge delta=${layout.actionsLeft - leftPaddingEdge})`);
    assert.ok(Math.abs(rightPaddingEdge - layout.brandRight) <= edgeTolerance,
      `LTR branding anchors to the header right padding at ${width}px (edge delta=${rightPaddingEdge - layout.brandRight})`);
    assert.ok(layout.actionsRight <= layout.brandLeft,
      `LTR groups do not overlap at ${width}px (actions=${layout.actionsLeft}-${layout.actionsRight}, brand=${layout.brandLeft}-${layout.brandRight})`);
    if (width >= 768) assert.ok(layout.brandLeft - layout.actionsRight >= width * .1,
      `LTR leaves a flexible center gap at ${width}px`);
  } else {
    assert.ok(Math.abs(rightPaddingEdge - layout.actionsRight) <= edgeTolerance,
      `RTL utilities anchor to the header right padding at ${width}px (edge delta=${rightPaddingEdge - layout.actionsRight})`);
    assert.ok(Math.abs(layout.brandLeft - leftPaddingEdge) <= edgeTolerance,
      `RTL branding anchors to the header left padding at ${width}px (edge delta=${layout.brandLeft - leftPaddingEdge})`);
    assert.ok(layout.brandRight <= layout.actionsLeft,
      `RTL groups do not overlap at ${width}px (brand=${layout.brandLeft}-${layout.brandRight}, actions=${layout.actionsLeft}-${layout.actionsRight})`);
    if (width >= 768) assert.ok(layout.actionsLeft - layout.brandRight >= width * .1,
      `RTL leaves a flexible center gap at ${width}px`);
  }
  if (width <= 560) {
    assert.ok(layout.barHeight <= 70, 'compact mobile header is not made taller');
    assert.ok(layout.logoHeight <= 44, 'mobile logo retains its existing compact height');
    assert.equal(layout.userInfoDisplay, 'none', 'mobile profile text remains compact');
  }
  assert.ok(Math.abs(layout.brandCenterY - layout.barCenterY) <= 1,
    `branding is vertically centered at ${width}px`);
  assert.ok(Math.abs(layout.actionsCenterY - layout.barCenterY) <= 1,
    `header actions are vertically centered at ${width}px`);
  assert.equal(layout.logoObjectFit, 'contain', 'logo preserves its aspect ratio without cropping');
  const expectedLogoMaxHeight = width > 1100 ? 45 : width <= 380 ? 34 : 40;
  assert.equal(layout.logoMaxHeight, expectedLogoMaxHeight,
    `logo uses the responsive ${expectedLogoMaxHeight}px size cap at ${width}px`);
  assert.deepEqual(layout.actionChildren, [
    'header-search-trigger',
    'header-language-switcher',
    'notification-dropdown-wrapper',
    'profile-dropdown-wrapper',
  ], 'utility/profile controls keep their existing internal order');
}

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    for (const width of [1440, 1024, 768, 430, 390, 375]) {
      for (const theme of ['light', 'dark']) {
        for (const direction of ['ltr', 'rtl']) {
          await page.setViewport({ width, height: width <= 430 ? (width === 430 ? 932 : 844) : 900 });
          await page.setContent(pageMarkup(direction, theme));
          assertDirection(await positions(page), direction, width);
        }
      }
    }

    await page.setViewport({ width: 1440, height: 900 });
    await page.setContent(pageMarkup('ltr', 'light'));
    assertDirection(await positions(page), 'ltr', 1440);
    await page.evaluate(() => document.documentElement.setAttribute('dir', 'rtl'));
    assertDirection(await positions(page), 'rtl', 1440);
    await page.evaluate(() => document.documentElement.setAttribute('dir', 'ltr'));
    assertDirection(await positions(page), 'ltr', 1440);
    console.log('Header directional alignment rendered geometry: PASS');
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
