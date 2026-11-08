const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const puppeteer = require('puppeteer');

const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const readHead = file => execFileSync('git', ['show', `HEAD:${file}`], { cwd: root, encoding: 'utf8' });
const sharedFiles = [
  'css/layout.css',
  'css/components.css',
  'css/theme-foundation.css',
  'css/component-semantic-migration.css',
  'css/ui-01-production-layout.css',
  'css/ui-02-structural-layout.css',
];

const fixture = (theme, direction, styles) => `<!doctype html><html lang="${direction === 'rtl' ? 'ar' : 'en'}" dir="${direction}" data-theme="${theme}"><head><meta charset="utf-8"><style>${styles}</style></head><body>
  <div class="app-container">
    <aside class="sidebar"><div class="sidebar-header"><strong>MUQAM HR</strong></div><nav class="sidebar-nav"><a class="nav-item active"><span>Dashboard</span></a><a class="nav-item"><span>Employee Directory</span></a><a class="nav-item"><span>Reports</span></a></nav></aside>
    <main class="main-content">
      <header class="topbar"><div class="header-brand-group"><strong>HR.sys</strong></div><div class="topbar-actions"><button class="icon-btn">☾</button><span class="user-name">Test Manager</span></div></header>
      <section class="view-container"><div class="page-header"><div><p class="page-subtitle">Operations</p><h1 class="page-title">${direction === 'rtl' ? 'لوحة التحكم' : 'Dashboard'}</h1></div><button class="btn btn-primary">${direction === 'rtl' ? 'إجراء سريع' : 'Quick action'}</button></div>
        <div class="dashboard-grid">
          <article class="card col-span-4"><h2 class="card-title">${direction === 'rtl' ? 'صحة المستندات' : 'Document Health'}</h2><p class="page-subtitle">12 documents need review</p><button class="btn btn-secondary">View details</button></article>
          <article class="card col-span-4"><h2 class="card-title">${direction === 'rtl' ? 'المهام' : 'Task Manager'}</h2><div class="task-v2-toolbar"><input class="form-control" placeholder="Search tasks"><select class="form-control"><option>All statuses</option></select></div><div class="task-v2-row"><strong>Prepare monthly report</strong><span class="semantic-status">In progress</span></div></article>
          <article class="card col-span-4"><h2 class="card-title">${direction === 'rtl' ? 'إعلانات' : 'Announcements'}</h2><p class="page-subtitle">Company updates and operating notes</p><a href="#">Read all</a></article>
          <article class="card col-span-12"><h2 class="card-title">${direction === 'rtl' ? 'دليل الموظفين' : 'Employee Directory'}</h2><div class="table-responsive"><table class="data-table"><thead><tr><th>Name</th><th>Status</th><th>Department</th></tr></thead><tbody><tr><td>Montasir Ahmed</td><td><span class="badge">Clocked in</span></td><td>Operations</td></tr></tbody></table></div></article>
          <article class="card col-span-6"><h2 class="card-title">CRM workspace</h2><div class="tw-bg-white tw-border tw-border-slate-200 tw-p-4"><span class="tw-text-slate-700">Client pipeline and projects</span></div></article>
          <article class="card col-span-6"><h2 class="card-title">Secure Workspace</h2><input class="form-control" placeholder="Enter a value"><button class="btn btn-danger">Delete</button></article>
        </div>
      </section>
    </main>
  </div>
</body></html>`;

function stylesheet(includeGlobal, before) {
  const variableFile = before ? 'css/variables.css' : 'css/variables.css';
  const variables = before ? readHead(variableFile) : read(variableFile);
  return [variables, ...sharedFiles.map(file => before ? readHead(file) : read(file)), includeGlobal ? read('css/cyber-obsidian-theme.css') : ''].join('\n');
}

(async () => {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });
  const outputDir = path.join(root, 'artifacts', 'cyber-obsidian-global-theme');
  fs.mkdirSync(outputDir, { recursive: true });
  try {
    const scenarios = [];
    for (const width of [320, 360, 390, 430, 768, 1024, 1280, 1440, 1920]) {
      for (const direction of ['ltr', 'rtl']) {
        for (const theme of ['light', 'dark']) {
          const isCapture = (width === 1440 && direction === 'ltr' && theme === 'dark')
            || (width === 390 && direction === 'rtl' && theme === 'dark')
            || (width === 1440 && direction === 'ltr' && theme === 'light');
          scenarios.push({
            theme,
            direction,
            width,
            height: width <= 430 ? 844 : 1000,
            name: `${width}-${direction}-${theme}`,
            capture: isCapture,
            captureName: width === 1440 && direction === 'ltr' && theme === 'dark'
              ? 'desktop-1440-en-dark'
              : width === 390 && direction === 'rtl' && theme === 'dark'
                ? 'mobile-390-ar-dark'
                : 'desktop-1440-en-light',
          });
        }
      }
    }
    for (const scenario of scenarios) {
      const page = await browser.newPage();
      await page.setViewport({ width: scenario.width, height: scenario.height, deviceScaleFactor: 1 });
      await page.setContent(fixture(scenario.theme, scenario.direction, stylesheet(true, false)));
      const state = await page.evaluate(() => {
        const card = document.querySelector('.card');
        const sidebar = document.querySelector('.sidebar');
        const input = document.querySelector('.form-control');
        const rootStyle = getComputedStyle(document.documentElement);
        return {
          theme: rootStyle.getPropertyValue('--bg-app').trim(),
          body: getComputedStyle(document.body).backgroundColor,
          card: getComputedStyle(card).backgroundColor,
          sidebar: getComputedStyle(sidebar).backgroundColor,
          input: getComputedStyle(input).backgroundColor,
          scrollWidth: document.body.scrollWidth,
          viewportWidth: innerWidth,
          overflow: [...document.querySelectorAll('*')].filter(element => !element.closest('.table-responsive')).map(element => ({ tag: element.tagName, className: element.className, left: element.getBoundingClientRect().left, right: element.getBoundingClientRect().right })).filter(item => item.right > innerWidth + 1 || item.left < -1).slice(0, 12),
        };
      });
      if (scenario.theme === 'dark') {
        assert.equal(state.theme, '#0F172A', `${scenario.name}: dark app token`);
        assert.equal(state.body, 'rgb(15, 23, 42)', `${scenario.name}: body surface`);
        assert.equal(state.card, 'rgb(30, 41, 59)', `${scenario.name}: card surface`);
        assert.equal(state.sidebar, 'rgb(30, 41, 59)', `${scenario.name}: navigation surface`);
        assert.equal(state.input, 'rgb(30, 41, 59)', `${scenario.name}: input surface`);
      }
      assert.deepEqual(state.overflow, [], `${scenario.name}: no viewport overflow ${JSON.stringify(state)}`);
      if (scenario.capture) await page.screenshot({ path: path.join(outputDir, `${scenario.captureName}-after.png`), fullPage: true });
      await page.close();
    }

    const beforePage = await browser.newPage();
    await beforePage.setViewport({ width: 1440, height: 1000, deviceScaleFactor: 1 });
    await beforePage.setContent(fixture('dark', 'ltr', stylesheet(false, true)));
    await beforePage.screenshot({ path: path.join(outputDir, 'desktop-1440-en-dark-before.png'), fullPage: true });
    await beforePage.close();
    console.log(`Global Cyber Obsidian rendered checks and screenshots passed: ${outputDir}`);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
