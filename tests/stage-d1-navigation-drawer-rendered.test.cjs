const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const css = [
  fs.readFileSync(path.join(root, 'css/variables.css'), 'utf8'),
  fs.readFileSync(path.join(root, 'css/layout.css'), 'utf8'),
].join('\n');

const requiredLinks = [
  'Dashboard', 'My Day', 'Task Manager', 'Projects',
  'Time & Attendance', 'Employee Requests',
  'Contracts', 'Documents', 'Approvals',
];

function fixture(direction) {
  const groups = direction === 'rtl'
    ? [
        ['مساحة العمل', ['لوحة القيادة', 'يومي', 'إدارة المهام', 'المشاريع']],
        ['الأفراد والموارد البشرية', ['الوقت والحضور', 'طلبات الموظفين']],
        ['الأعمال / المزيد', ['العقود', 'المستندات', 'الموافقات']],
      ]
    : [
        ['Workspace', ['Dashboard', 'My Day', 'Task Manager', 'Projects']],
        ['People & HR', ['Time & Attendance', 'Employee Requests']],
        ['Business / More', ['Contracts', 'Documents', 'Approvals']],
      ];
  const sections = groups.map(([label, items]) =>
    `<section class="navigation-drawer-group"><h3>${label}</h3>${items.map((name, index) =>
      `<button class="navigation-drawer-item${index === 0 && label === groups[0][0] ? ' active' : ''}"${index === 0 && label === groups[0][0] ? ' aria-current="page"' : ''}><svg aria-hidden="true"></svg><span>${name}</span></button>`
    ).join('')}</section>`
  ).join('');

  return `<!doctype html><html dir="${direction}" data-theme="dark"><head><meta charset="utf-8"><style>${css}</style></head><body>
    <main class="app-container"><section class="main-content"><header class="topbar"></header></section></main>
    <div id="appNavigationDrawerOverlay" class="app-navigation-drawer-overlay is-open">
      <button class="navigation-drawer-backdrop" aria-label="Close"></button>
      <aside class="app-navigation-drawer" role="dialog" aria-modal="true" aria-labelledby="navigation-drawer-title" dir="${direction}">
        <header class="navigation-drawer-header"><div class="navigation-drawer-brand-group"><div class="navigation-drawer-brand"><img class="navigation-drawer-brand-logo-dark" alt="MUQAM HR"></div><h2 id="navigation-drawer-title">${direction === 'rtl' ? 'التنقل' : 'Navigation'}</h2></div><button class="navigation-drawer-close" aria-label="Close">Close</button></header>
        <nav class="navigation-drawer-list" aria-label="Navigation">${sections}</nav>
      </aside>
    </div>
    <script>document.querySelector('.navigation-drawer-backdrop').addEventListener('click',()=>document.querySelector('#appNavigationDrawerOverlay').remove())</script>
  </body></html>`;
}

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    for (const scenario of [
      { direction: 'ltr', width: 1440, height: 900, edge: 'left' },
      { direction: 'rtl', width: 1440, height: 900, edge: 'right' },
      { direction: 'rtl', width: 390, height: 844, edge: 'right' },
    ]) {
      await page.setViewport({ width: scenario.width, height: scenario.height });
      await page.setContent(fixture(scenario.direction));
      const result = await page.evaluate(() => {
        const drawer = document.querySelector('.app-navigation-drawer');
        const rect = drawer.getBoundingClientRect();
        const style = getComputedStyle(drawer);
        return {
          left: rect.left,
          right: rect.right,
          width: rect.width,
          top: rect.top,
          bottom: rect.bottom,
          position: style.position,
          cssTop: style.top,
          cssBottom: style.bottom,
          height: rect.height,
          rows: [...drawer.querySelectorAll('.navigation-drawer-item')].map(row => ({
            display: getComputedStyle(row).display,
            height: row.getBoundingClientRect().height,
            label: row.innerText.trim(),
          })),
          legacyTiles: drawer.querySelectorAll('.more-tile,.more-grid,.more-card,.mobile-navigation-panel,.mobile-navigation-grid,.mobile-navigation-item').length,
          dialog: drawer.getAttribute('role') === 'dialog' && drawer.getAttribute('aria-modal') === 'true',
        };
      });

      assert.equal(result.position, 'fixed', `${scenario.direction} drawer itself is viewport-fixed, not centered inside a legacy sheet`);
      assert.equal(result.cssTop, '0px', 'CSS anchors the drawer top to the viewport');
      assert.equal(result.cssBottom, '0px', 'CSS anchors the drawer bottom to the viewport');
      assert.equal(result.top, 0, 'drawer is attached to the top viewport edge');
      assert.equal(result.bottom, scenario.height, 'drawer spans the viewport height');
      assert.ok(Math.abs(result.height - scenario.height) <= 2, `drawer height matches viewport (height=${result.height}, viewport=${scenario.height})`);
      assert.equal(result.dialog, true, 'drawer remains an accessible modal navigation panel');
      assert.equal(result.legacyTiles, 0, 'legacy tile UI is not rendered inside the drawer');
      assert.deepEqual(result.rows.map(row => row.label), scenario.direction === 'rtl'
        ? ['لوحة القيادة', 'يومي', 'إدارة المهام', 'المشاريع', 'الوقت والحضور', 'طلبات الموظفين', 'العقود', 'المستندات', 'الموافقات']
        : requiredLinks);
      assert.ok(result.rows.every(row => row.display === 'flex' && row.height >= 44 && row.height <= 52), 'navigation entries are 44-52px vertical rows');

      if (scenario.edge === 'left') {
        assert.ok(Math.abs(result.left) <= 1, `LTR drawer touches left edge (left=${result.left})`);
        assert.ok(result.right > result.left, 'LTR drawer has positive width at the left edge');
        assert.ok(result.right < scenario.width / 2, 'LTR drawer is not horizontally centered');
      } else {
        assert.ok(Math.abs(result.right - scenario.width) <= 1, `RTL drawer touches right edge (right=${result.right})`);
        assert.ok(result.right > result.left, 'RTL drawer has positive width at the right edge');
        const drawerCenter = (result.left + result.right) / 2;
        assert.ok(Math.abs(drawerCenter - scenario.width / 2) > 2, `RTL drawer is not horizontally centered (left=${result.left}, width=${result.width}, viewport=${scenario.width})`);
      }
      if (scenario.width < 600) {
        const expected = Math.min(scenario.width * 0.86, 340);
        assert.ok(Math.abs(result.width - expected) <= 2, `mobile width matches min(86vw, 340px) (width=${result.width}, expected=${expected})`);
      } else {
        assert.ok(Math.abs(result.width - 320) <= 2, `desktop drawer is 320px (width=${result.width})`);
      }
    }
    console.log('Stage D.1 rendered navigation drawer geometry checks passed.');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
