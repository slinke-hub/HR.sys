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
    <header class="topbar" style="width: 100vw; box-sizing: border-box;">
        <div class="topbar-actions"><button>Search</button><button>Language</button><button>Notifications</button><button>Profile</button></div>
        <div class="header-brand-group"><button class="header-navigation-toggle" aria-label="Open navigation"><svg aria-hidden="true"></svg></button><div class="header-logo"><img class="app-logo" alt="Brand"></div></div>
    </header>
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
      ...[1440, 1024, 768, 430, 390].flatMap(width => [
        { direction: 'ltr', width, height: width <= 430 ? (width === 390 ? 844 : 932) : 900, edge: 'right' },
        { direction: 'rtl', width, height: width <= 430 ? (width === 390 ? 844 : 932) : 900, edge: 'left' },
      ]),
    ]) {
      await page.setViewport({ width: scenario.width, height: scenario.height });
      await page.setContent(fixture(scenario.direction));
      const result = await page.evaluate(() => {
        const drawer = document.querySelector('.app-navigation-drawer');
        const rect = drawer.getBoundingClientRect();
        const style = getComputedStyle(drawer);
        const headerRect = document.querySelector('.topbar').getBoundingClientRect();
        const hamburgerRect = document.querySelector('.header-navigation-toggle').getBoundingClientRect();
        const hamburgerEdge = hamburgerRect.left - headerRect.left <= headerRect.right - hamburgerRect.right ? 'left' : 'right';
        const drawerEdge = Math.abs(rect.left) <= 1 ? 'left' : Math.abs(rect.right - innerWidth) <= 1 ? 'right' : 'center';
        return {
          left: rect.left,
          right: rect.right,
          width: rect.width,
          top: rect.top,
          bottom: rect.bottom,
          position: style.position,
          openTransform: style.transform,
          transitionProperty: style.transitionProperty,
          transitionDuration: style.transitionDuration,
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
          hamburgerLeft: hamburgerRect.left,
          hamburgerRight: hamburgerRect.right,
          headerLeft: headerRect.left,
          headerRight: headerRect.right,
          hamburgerEdge,
          drawerEdge,
          hiddenTransform: (() => {
            const overlay = document.querySelector('#appNavigationDrawerOverlay');
            drawer.style.transition = 'none';
            overlay.classList.remove('is-open');
            const value = getComputedStyle(drawer).transform;
            overlay.classList.add('is-open');
            const match = value.match(/^matrix\([^,]+,[^,]+,[^,]+,[^,]+,([^,]+)/);
            return match ? Number(match[1]) : NaN;
          })(),
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
      assert.equal(result.openTransform, 'matrix(1, 0, 0, 1, 0, 0)', 'open drawer begins at the selected physical edge with no opposite-side flash');
      assert.ok(result.transitionProperty.includes('transform'), 'drawer edge movement is animated');
      assert.ok(parseFloat(result.transitionDuration) >= 0.2, 'drawer open/close animation retains its transition duration');
      assert.deepEqual(result.rows.map(row => row.label), scenario.direction === 'rtl'
        ? ['لوحة القيادة', 'يومي', 'إدارة المهام', 'المشاريع', 'الوقت والحضور', 'طلبات الموظفين', 'العقود', 'المستندات', 'الموافقات']
        : requiredLinks);
      assert.ok(result.rows.every(row => row.display === 'flex' && row.height >= 44 && row.height <= 52), 'navigation entries are 44-52px vertical rows');

      if (scenario.edge === 'left') {
        assert.ok(Math.abs(result.left) <= 1, `RTL drawer touches left edge (left=${result.left})`);
        assert.ok(result.right > result.left, 'RTL drawer has positive width at the left edge');
        const drawerCenter = (result.left + result.right) / 2;
        assert.ok(Math.abs(drawerCenter - scenario.width / 2) > 2, `RTL drawer is not horizontally centered (left=${result.left}, width=${result.width}, viewport=${scenario.width})`);
        assert.ok(result.hiddenTransform < 0, 'RTL drawer closes toward the left physical edge');
      } else {
        assert.ok(Math.abs(result.right - scenario.width) <= 1, `LTR drawer touches right edge (right=${result.right})`);
        assert.ok(result.right > result.left, 'LTR drawer has positive width at the right edge');
        const drawerCenter = (result.left + result.right) / 2;
        assert.ok(Math.abs(drawerCenter - scenario.width / 2) > 2, `LTR drawer is not horizontally centered (left=${result.left}, width=${result.width}, viewport=${scenario.width})`);
        assert.ok(result.hiddenTransform > 0, 'LTR drawer closes toward the right physical edge');
      }
      assert.equal(result.drawerEdge, result.hamburgerEdge, `${scenario.direction.toUpperCase()} drawer attaches to same physical edge as hamburger`);
      if (scenario.direction === 'ltr') {
        assert.equal(result.hamburgerEdge, 'right', `LTR hamburger is physically nearer the right header edge (left=${result.hamburgerLeft}, right=${result.hamburgerRight})`);
      } else {
        assert.equal(result.hamburgerEdge, 'left', `RTL hamburger is physically nearer the left header edge (left=${result.hamburgerLeft}, right=${result.hamburgerRight})`);
      }
      if (scenario.width < 600) {
        const expected = Math.min(scenario.width * 0.86, 340);
        assert.ok(Math.abs(result.width - expected) <= 2, `mobile width matches min(86vw, 340px) (width=${result.width}, expected=${expected})`);
      } else {
        assert.ok(Math.abs(result.width - 320) <= 2, `desktop drawer is 320px (width=${result.width})`);
      }
    }
    await page.setViewport({ width: 1440, height: 900 });
    await page.setContent(fixture('ltr'));
    const liveSwitch = await page.evaluate(() => {
      const html = document.documentElement;
      const drawer = document.querySelector('.app-navigation-drawer');
      const hamburger = document.querySelector('.header-navigation-toggle');
      const measure = () => {
        const d = drawer.getBoundingClientRect();
        const h = hamburger.getBoundingClientRect();
        return {
          drawer: Math.abs(d.left) <= 1 ? 'left' : Math.abs(d.right - innerWidth) <= 1 ? 'right' : 'center',
          hamburger: h.left < innerWidth / 2 ? 'left' : 'right',
        };
      };
      const states = [measure()];
      html.dir = 'rtl';
      drawer.dir = 'rtl';
      states.push(measure());
      html.dir = 'ltr';
      drawer.dir = 'ltr';
      states.push(measure());
      return states;
    });
    assert.deepEqual(liveSwitch, [
      { drawer: 'right', hamburger: 'right' },
      { drawer: 'left', hamburger: 'left' },
      { drawer: 'right', hamburger: 'right' },
    ], 'live LTR to RTL to LTR switching keeps drawer and hamburger on one physical edge');
    console.log('Stage D.1 rendered navigation drawer geometry checks passed.');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
