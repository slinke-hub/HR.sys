const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const styles = [
  'css/variables.css',
  'css/layout.css',
  'css/components.css',
  'css/theme-foundation.css',
  'css/component-semantic-migration.css',
].map(file => fs.readFileSync(path.join(root, file), 'utf8')).join('\n');

const fixture = direction => `<!doctype html><html dir="${direction}" data-theme="light"><head><meta charset="utf-8"><style>${styles}</style></head><body>
  <main class="app-container"><section class="view-container"><header class="page-header">
    <div><h1 class="page-title">Dashboard</h1></div>
    <button id="attendanceClockButton" class="employees-radar-clockout dashboard-attendance-clockout" aria-label="Clock Out">
      ${direction === 'rtl' ? '<span class="dashboard-clock-button-label">تسجيل الخروج</span><svg aria-hidden="true"></svg>' : '<svg aria-hidden="true"></svg><span class="dashboard-clock-button-label">Clock Out</span>'}
    </button>
  </header><button class="employees-radar-clockout"><svg></svg><span>Clock out</span></button></section></main>
</body></html>`;

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    for (const width of [1440, 1024, 768, 430, 390]) {
      for (const direction of ['ltr', 'rtl']) {
        for (const theme of ['light', 'dark']) {
          await page.setViewport({ width, height: width === 390 ? 844 : width <= 430 ? 932 : 900 });
          await page.setContent(fixture(direction));
          await page.evaluate(themeName => { document.documentElement.dataset.theme = themeName; }, theme);
          const result = await page.evaluate(() => {
            const main = document.querySelector('#attendanceClockButton');
            const radar = document.querySelector('.employees-radar-clockout:not(#attendanceClockButton)');
            const mainStyle = getComputedStyle(main);
            const radarStyle = getComputedStyle(radar);
            const rect = main.getBoundingClientRect();
            const properties = ['backgroundColor', 'borderColor', 'borderRadius', 'fontFamily', 'fontSize', 'fontWeight', 'gap', 'minHeight', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'color'];
            return {
              rect: { left: rect.left, right: rect.right, width: rect.width, height: rect.height },
              viewportWidth: innerWidth,
              scrollWidth: document.documentElement.scrollWidth,
              labelVisible: getComputedStyle(main.querySelector('span')).display !== 'none',
              hasExitIcon: Boolean(main.querySelector('svg')),
              sameCoreStyle: properties.every(property => mainStyle[property] === radarStyle[property]),
            };
          });
          assert.ok(result.sameCoreStyle, `${direction}/${theme}/${width}: main action shares Radar semantic styles`);
          assert.ok(result.rect.width > result.rect.height, `${direction}/${theme}/${width}: action remains compact, not square`);
          assert.ok(result.rect.width < result.viewportWidth, `${direction}/${theme}/${width}: action does not stretch across the viewport`);
          assert.equal(result.scrollWidth, result.viewportWidth, `${direction}/${theme}/${width}: no horizontal overflow`);
          assert.equal(result.labelVisible, true, `${direction}/${theme}/${width}: Clock Out label remains visible`);
          assert.equal(result.hasExitIcon, true, `${direction}/${theme}/${width}: exit icon remains visible`);
        }
      }
    }
    console.log('Dashboard Clock Out rendered style checks passed at 1440/1024/768/430/390, LTR/RTL, Light/Dark.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
